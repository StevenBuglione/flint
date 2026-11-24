/// Cooperative deadline and native descriptor waits.
module flint.engine.sql.sys.wait;

import core.atomic : atomicLoad, atomicOp, atomicStore, cas;
import flint.arena : Error, Status;
import flint.conc : Context, Deadline;
import flint.conc.park : park, wakeAll;
import flint.engine.reactor : NativeInterest, Reactor, RemoteWaker, TaskWaker;
import flint.engine.sql.ffi.shim : Interest, waitOffReactor;
import flint.engine.sql.sys.diagnostics : diagnosticNow, noteSocketWait;

@safe:

/// A leased connection's descriptor watch on this worker. It stays registered across the statements of a lease,
/// saving a watch and an unwatch (two system calls) per wait, and is dropped when the lease is released.
private struct Signal
{
    int descriptor = -1;
    /// The lease whose connection owns the descriptor.
    ulong lease;
    /// The interest the watch is registered with; zero before it is registered.
    uint events;
    /// A fiber waits on the descriptor now.
    bool waiting;
    bool ready;
    TaskWaker waker;

    void receive(int fd, NativeInterest seen) nothrow @nogc
    {
        if (descriptor != fd || seen == NativeInterest.none)
            return;
        if (!waiting)
        {
            // Readiness between statements (a server notice): nobody reads it yet, and the level-triggered watch
            // would report it on every pass, so drop the watch; the next wait registers it again.
            cast(void) Reactor.current().unwatchNative(fd);
            this = Signal.init;
            return;
        }
        ready = true;
        // The watch is level-triggered: until the waiting fiber reads, every loop pass reports the descriptor
        // again, so resume it on the next pass rather than at its fallback deadline.
        cast(void) Reactor.current().wake(waker);
    }
}

/// How long a fiber waiting on a watched descriptor sleeps before re-checking without a wake. The watch's wake
/// resumes it first; this only bounds a missed one.
private enum fallbackMillis = 1_000;

private Signal[256] signals;

/// The entry for `fd` held by `lease` on this worker, a new one, or `size_t.max` when the table is full. An entry
/// for the same descriptor under another lease is stale (its connection closed elsewhere) and is replaced.
private size_t signalFor(int fd, ulong lease) nothrow @nogc
{
    size_t free = size_t.max;
    foreach (index, ref signal; signals)
    {
        if (signal.descriptor == fd)
        {
            if (signal.lease == lease)
                return index;
            cast(void) Reactor.current().unwatchNative(fd);
            signal = Signal(fd, lease);
            return index;
        }
        if (signal.descriptor == -1 && free == size_t.max)
            free = index;
    }
    if (free != size_t.max)
        signals[free] = Signal(fd, lease);
    return free;
}

/// Drop the descriptor watches `lease` holds on this worker, before its connection may close.
package(flint.engine.sql) void releaseWatches(ulong lease) nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() == uint.max)
        return;
    foreach (ref signal; signals)
    {
        if (signal.descriptor == -1 || signal.lease != lease)
            continue;
        if (signal.events != 0)
            cast(void) owner.unwatchNative(signal.descriptor);
        signal = Signal.init;
    }
}

package(flint.engine.sql) Error admit() nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() != uint.max && !owner.currentTask().ok())
        return Error(Status.conflict, "SQL calls on a reactor require a task fiber");
    return Error.init;
}

package(flint.engine.sql) Error admitStartup() nothrow @nogc
{
    auto owner = Reactor.current();
    return owner.currentCore() == uint.max ? Error.init : Error(Status.conflict,
            "whole SQL programs require startup outside the reactor");
}

// Per-pool generation of lease-queue changes. Off-reactor waiters sleep on it instead of polling,
// because the FIFO head would otherwise hold every released lease until its next poll.
private shared uint[64] leaseEpochs;
private shared uint[64] leaseSleepers;

/// Register a waiter before the acquisition attempt whose failure it may sleep on.
package(flint.engine.sql) void joinLeaseQueue(ulong pool) nothrow @nogc
{
    atomicOp!"+="(leaseSleepers[pool % leaseSleepers.length], 1U);
}

/// Remove a waiter registered by joinLeaseQueue.
package(flint.engine.sql) void leaveLeaseQueue(ulong pool) nothrow @nogc
{
    atomicOp!"-="(leaseSleepers[pool % leaseSleepers.length], 1U);
}

/// Waiters registered on the pool, for diagnostics.
package(flint.engine.sql) uint leaseWaiterCount(ulong pool) nothrow @nogc
{
    return atomicLoad(leaseSleepers[pool % leaseSleepers.length]);
}

/// Observe the pool's lease generation before an acquisition attempt.
package(flint.engine.sql) uint leaseMark(ulong pool) nothrow @nogc
{
    return atomicLoad(leaseEpochs[pool % leaseEpochs.length]);
}

/// Announce a returned lease or a changed queue head to registered waiters. A waiter registers
/// before its failed attempt, so a change ordered after that attempt always observes it. Off-reactor
/// waiters wake on the epoch; the reactor waiter holding the lowest ticket, the queue's head, is
/// signalled through the handle it armed before its attempt.
package(flint.engine.sql) void leaseChanged(ulong pool) nothrow @nogc
{
    const index = pool % leaseEpochs.length;
    if (atomicLoad(leaseSleepers[index]) == 0)
        return;
    atomicOp!"+="(leaseEpochs[index], 1U);
    wakeAll(leaseEpochs[index]);
    auto head = leaseHead(pool);
    if (head.valid)
        cast(void) head.signal();
}

/// The C core calls this when a connection's asynchronous retirement finishes, freeing its slot for the queue.
private extern (C) void leaseRetired(ulong pool) nothrow @nogc
{
    leaseChanged(pool);
}

/// The function the C core calls when a retired connection's slot becomes free (`flint_sql_set_retired_hook`).
package(flint.engine.sql) auto retiredHook() nothrow @nogc
{
    return &leaseRetired;
}

/// Arm the calling reactor fiber's next yield for a lease handoff, before the acquisition attempt it follows; an
/// empty handle off the reactor.
package(flint.engine.sql) RemoteWaker armLeaseWait() nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() == uint.max)
        return RemoteWaker.init;
    auto armed = owner.armRemoteWake();
    return armed.ok() ? armed.value : RemoteWaker.init;
}

/// Wait for a lease-queue change after mark, until `until` (monotonic nanoseconds) at the latest. A reactor fiber
/// holding `ticket` waits for the signal its `armed` handle receives when it is the queue head; off the reactor the
/// thread sleeps on the epoch. Both re-check at least every `leaseFallbackMillis` (every 2 ms off the reactor).
package(flint.engine.sql) Error pauseForLease(ulong pool, uint mark, ulong ticket, RemoteWaker armed,
        long until, ref const Context context) nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() == uint.max)
    {
        park(leaseEpochs[pool % leaseEpochs.length], mark, 2_000_000);
        return Error.init;
    }
    if (ticket == 0 || !armed.valid || !rememberLeaseWaiter(pool, ticket, armed))
        return owner.yieldUntil(Deadline.afterMillis(1), context);
    // A release after the failed attempt but before the registration above announced itself in the epoch.
    if (leaseMark(pool) != mark)
        return Error.init;
    auto wake = Deadline.afterMillis(leaseFallbackMillis);
    if (until < wake.monotonicNanoseconds)
        wake = Deadline(until);
    return owner.yieldUntil(wake, context);
}

/// How long a queued reactor fiber sleeps without a signal before re-checking: a safety net only, since the
/// release, withdrawal or retirement that frees a lease signals the queue head.
private enum leaseFallbackMillis = 100;

/// A reactor fiber queued for a lease: its FIFO ticket and the handle that ends its current wait.
private struct LeaseWaiter
{
    ulong ticket;
    RemoteWaker waker;
}

/// The reactor fibers queued on one pool slot, below the high-water mark `used`.
private struct LeaseWaiters
{
    shared bool locked;
    LeaseWaiter[] entries;
    size_t used;
}

private __gshared LeaseWaiters[64] leaseWaiters;

/// Reserve room for `capacity` reactor waiters on a pool slot. Called when the pool opens, before any waiter.
// SAFETY: A slot's table is replaced only here, while its pool is opening and has no waiters.
package(flint.engine.sql) @trusted void prepareLeaseWaiters(ulong pool, uint capacity)
{
    auto table = &leaseWaiters[pool % leaseWaiters.length];
    if (table.entries.length < capacity)
        table.entries = new LeaseWaiter[capacity];
    else
        table.entries[] = LeaseWaiter.init;
    table.used = 0;
}

// SAFETY: The spin lock serializes every access to the slot's table, which only prepareLeaseWaiters resizes.
private @trusted LeaseWaiters* lockWaiters(ulong pool) nothrow @nogc
{
    auto table = &leaseWaiters[pool % leaseWaiters.length];
    while (!cas(&table.locked, false, true))
    {
    }
    return table;
}

private void unlockWaiters(LeaseWaiters* table) nothrow @nogc
{
    atomicStore(table.locked, false);
}

/// Record or refresh the handle of the waiter holding `ticket`. False when the table is full or missing.
private bool rememberLeaseWaiter(ulong pool, ulong ticket, RemoteWaker waker) nothrow @nogc
{
    auto table = lockWaiters(pool);
    scope (exit)
        unlockWaiters(table);
    size_t free = size_t.max;
    foreach (index, ref entry; table.entries[0 .. table.used])
    {
        if (entry.ticket == ticket)
        {
            entry.waker = waker;
            return true;
        }
        if (entry.ticket == 0 && free == size_t.max)
            free = index;
    }
    if (free == size_t.max)
    {
        if (table.used == table.entries.length)
            return false;
        free = table.used++;
    }
    table.entries[free] = LeaseWaiter(ticket, waker);
    return true;
}

/// Forget the waiter holding `ticket`, once it acquired or withdrew.
package(flint.engine.sql) void forgetLeaseWaiter(ulong pool, ulong ticket) nothrow @nogc
{
    if (ticket == 0)
        return;
    auto table = lockWaiters(pool);
    scope (exit)
        unlockWaiters(table);
    foreach (ref entry; table.entries[0 .. table.used])
    {
        if (entry.ticket != ticket)
            continue;
        entry = LeaseWaiter.init;
        break;
    }
    while (table.used != 0 && table.entries[table.used - 1].ticket == 0)
        --table.used;
}

/// The handle of the reactor waiter with the lowest ticket, the FIFO head among them, or an empty handle.
private RemoteWaker leaseHead(ulong pool) nothrow @nogc
{
    auto table = lockWaiters(pool);
    scope (exit)
        unlockWaiters(table);
    ulong lowest = ulong.max;
    RemoteWaker head;
    foreach (ref entry; table.entries[0 .. table.used])
    {
        if (entry.ticket != 0 && entry.ticket < lowest)
        {
            lowest = entry.ticket;
            head = entry.waker;
        }
    }
    return head;
}

package(flint.engine.sql) Error pause() nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() == uint.max)
        return Error(waitOffReactor(Interest.init, 2));
    return owner.yieldUntil(Deadline.afterMillis(1));
}

private bool continueWaiting(ref const Context context, Deadline cleanup) nothrow @nogc
{
    if (cleanup == Deadline.init)
        return context.check().code == Status.ok;
    return Deadline.afterMillis(0).monotonicNanoseconds < cleanup.monotonicNanoseconds;
}

package(flint.engine.sql) Error waitFor(Interest want, ulong lease, ref const Context ctx, Deadline end) nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() == uint.max)
        return Error(waitOffReactor(want, 2));
    if (want.fd < 0)
        return owner.yieldUntil(Deadline.afterMillis(1));

    const waker = owner.currentWaker();
    if (!waker.ok())
        return waker.error;
    const index = signalFor(want.fd, lease);
    if (index == size_t.max)
        return owner.yieldUntil(Deadline.afterMillis(1));
    const watched = watchFor(owner, index, want);
    if (watched.code != Status.ok)
    {
        signals[index] = Signal.init;
        // Without native watches (Windows, ADR-026) the fiber re-checks every millisecond, as when they are exhausted.
        if (watched.code == Status.resourceExhausted || watched.code == Status.unsupported)
            return owner.yieldUntil(Deadline.afterMillis(1));
        return watched;
    }
    signals[index].waker = waker.value;
    signals[index].ready = false;
    signals[index].waiting = true;
    scope (exit)
        if (signals[index].descriptor == want.fd)
            signals[index].waiting = false;
    const started = diagnosticNow();
    scope (exit)
        noteSocketWait(started);
    return awaitSignal(owner, index, ctx, end);
}

/// Register the watch of the entry at `index` for `interest`, unless it already is.
private Error watchFor(ref Reactor owner, size_t index, Interest interest) nothrow @nogc
{
    if (signals[index].events == interest.events)
        return Error.init;
    const ready = &signals[index].receive;
    const status = owner.watchNative(interest.fd, cast(NativeInterest) interest.events, ready);
    if (status.code == Status.ok)
        signals[index].events = interest.events;
    return status;
}

/// Sleep until the signal at `index` is ready, the caller's context ends or cleanup expires.
private Error awaitSignal(ref Reactor owner, size_t index, ref const Context context, Deadline cleanup) nothrow @nogc
{
    while (!signals[index].ready && continueWaiting(context, cleanup))
    {
        const slept = sleepOnSignal(owner, context, cleanup);
        if (slept.contextEnded)
            return Error.init;
        if (slept.error.code != Status.ok)
            return slept.error;
    }
    return Error.init;
}

/// How one sleep on a signal ended.
private struct Slept
{
    /// A failure to report: the task's cancellation or the reactor stopping.
    Error error;
    /// The caller's context ended; the caller then cancels the statement and drains it under its cleanup deadline.
    bool contextEnded;
}

/// One sleep of a fiber waiting on its signal: the watch's wake or the fallback deadline resumes it, and so does
/// the end of the caller's context before cleanup starts.
private Slept sleepOnSignal(ref Reactor owner, ref const Context context, Deadline cleanup) nothrow @nogc
{
    auto fallback = Deadline.afterMillis(fallbackMillis);
    if (cleanup != Deadline.init)
    {
        if (cleanup.monotonicNanoseconds < fallback.monotonicNanoseconds)
            fallback = cleanup;
        return Slept(owner.yieldUntil(fallback));
    }
    const yielded = owner.yieldUntil(fallback, context);
    if (yielded.code != Status.ok && context.check().code != Status.ok)
        return Slept(Error.init, true);
    return Slept(yielded);
}
