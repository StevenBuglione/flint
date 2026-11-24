/// Cooperative deadline and native descriptor waits.
module flint.engine.sql.sys.wait;

import core.atomic : atomicLoad, atomicOp;
import flint.arena : Error, Status;
import flint.conc : Context, Deadline;
import flint.conc.park : park, wakeAll;
import flint.engine.reactor : NativeInterest, Reactor, TaskWaker;
import flint.engine.sql.ffi.shim : Interest, waitOffReactor;
import flint.engine.sql.sys.diagnostics : diagnosticNow, noteSocketWait;

@safe:

private struct Signal
{
    int descriptor = -1;
    bool ready;
    TaskWaker waker;

    void receive(int fd, NativeInterest events) nothrow @nogc
    {
        if (descriptor != fd || events == NativeInterest.none)
            return;
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

private size_t reserveSignal(int fd, TaskWaker waker) nothrow @nogc
{
    foreach (index, ref signal; signals)
    {
        if (signal.descriptor != -1)
            continue;
        signal = Signal(fd, false, waker);
        return index;
    }
    return size_t.max;
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
/// before its failed attempt, so a change ordered after that attempt always observes it.
package(flint.engine.sql) void leaseChanged(ulong pool) nothrow @nogc
{
    const index = pool % leaseEpochs.length;
    if (atomicLoad(leaseSleepers[index]) == 0)
        return;
    atomicOp!"+="(leaseEpochs[index], 1U);
    wakeAll(leaseEpochs[index]);
}

/// Wait for a lease-queue change after mark, bounded so asynchronous replacement is still observed.
package(flint.engine.sql) Error pauseForLease(ulong pool, uint mark) nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() != uint.max)
        return owner.yieldUntil(Deadline.afterMillis(1));
    park(leaseEpochs[pool % leaseEpochs.length], mark, 2_000_000);
    return Error.init;
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

package(flint.engine.sql) Error waitFor(Interest interest, ref const Context context, Deadline cleanup) nothrow @nogc
{
    auto owner = Reactor.current();
    if (owner.currentCore() == uint.max)
        return Error(waitOffReactor(interest, 2));
    if (interest.fd < 0)
        return owner.yieldUntil(Deadline.afterMillis(1));

    const waker = owner.currentWaker();
    if (!waker.ok())
        return waker.error;
    const index = reserveSignal(interest.fd, waker.value);
    if (index == size_t.max)
        return owner.yieldUntil(Deadline.afterMillis(1));
    scope (exit)
        signals[index] = Signal.init;

    const ready = &signals[index].receive;
    const status = owner.watchNative(interest.fd, cast(NativeInterest) interest.events, ready);
    // Without native watches (Windows, ADR-026) the fiber re-checks every millisecond, as when they are exhausted.
    if (status.code == Status.resourceExhausted || status.code == Status.unsupported)
        return owner.yieldUntil(Deadline.afterMillis(1));
    if (status.code != Status.ok)
        return status;
    scope (exit)
        owner.unwatchNative(interest.fd);
    const started = diagnosticNow();
    scope (exit)
        noteSocketWait(started);
    return awaitSignal(owner, index, context, cleanup);
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
