/// Cross-thread wakes of task fibers (`RemoteWaker`), without the mailbox: a thread other than the owner must be
/// able to resume a waiter even while every fiber slot is busy and the mailbox is full, which is exactly when a
/// released resource has to reach its next waiter.
///
/// Each owner has one lane: per fiber slot, the key of the wait the task armed and the highest key signalled for
/// that slot; a bitmap of slots with a signal to deliver; a notified flag; and a doorbell descriptor. Keys come
/// from one counter per owner and only increase, so a key names one wait of one task: a signal for an ended wait,
/// or for an earlier wait of the same task, never matches the armed key, and a late producer can never lower the
/// signalled key below a newer one.
module flint.engine.reactor.internal.wakes;

import core.atomic : atomicExchange, atomicLoad, atomicOp, atomicStore, cas;
import flint.arena : Status;
import flint.engine.reactor.sys.doorbell : Doorbell, closeDoorbell, drainDoorbell, openDoorbell, ringDoorbell;

@safe:

private enum wordBits = ulong.sizeof * 8;

/// What recording a signal found.
package(flint.engine.reactor) enum Recorded : ubyte
{
    /// No such slot, or an empty key.
    invalid,
    /// The wait the key names is not armed: it ended, a newer wait replaced it or the task finished.
    ended,
    /// Already signalled: the first signal delivers it.
    duplicate,
    /// This call recorded the signal first and must deliver it.
    fresh,
}

/// The `RemoteWaker.signal` status for a recording outcome.
package(flint.engine.reactor) Status statusOf(Recorded outcome) pure nothrow @nogc
{
    final switch (outcome)
    {
    case Recorded.invalid:
        return Status.invalidArgument;
    case Recorded.ended:
        return Status.notFound;
    case Recorded.duplicate:
    case Recorded.fresh:
        return Status.ok;
    }
}

/// One owner's remote-wake state. The owner arms and disarms; any thread signals.
package(flint.engine.reactor) struct WakeLane
{
    /// Per fiber slot: the key of the wait its task armed, or 0.
    shared(ulong)[] armed;
    /// Per fiber slot: the highest key signalled so far. Monotonic.
    shared(ulong)[] signalled;
    /// One bit per fiber slot with a signal the owner has not looked at yet.
    shared(ulong)[] ready;
    /// Set by the first signal after the owner's last drain; the doorbell rings only on that transition.
    shared bool notified;
    /// Signallers between their check of `closed` and their last use of the doorbell.
    shared uint writers;
    shared bool closed;
    Doorbell bell;
    /// Doorbell writes so far, for tests and diagnostics.
    shared ulong rings;
    /// Last key the owner issued. Owner only.
    ulong lastKey;

    @disable this(this);

    /// Size the lane for `slots` fiber slots and open its doorbell (none on Windows).
    bool initialize(uint slots) nothrow
    {
        armed = new shared(ulong)[slots];
        signalled = new shared(ulong)[slots];
        ready = new shared(ulong)[(slots + wordBits - 1) / wordBits];
        version (Posix)
            return openDoorbell(bell);
        else
            return true;
    }

    /// Owner: arm a new wait for `slot` and return its key.
    ulong arm(uint slot) nothrow @nogc
    {
        const key = ++lastKey;
        atomicStore(armed[slot], key);
        return key;
    }

    /// Owner: end `slot`'s armed wait, so later signals for it are rejected.
    void disarm(uint slot) nothrow @nogc
    {
        atomicStore(armed[slot], 0UL);
    }

    /// Owner: whether `slot`'s armed wait has been signalled.
    bool signalledNow(uint slot) const nothrow @nogc
    {
        const key = atomicLoad(armed[slot]);
        return key != 0 && atomicLoad(signalled[slot]) >= key;
    }

    /// Record a signal for `key` on `slot`. Any thread.
    Recorded record(uint slot, ulong key) nothrow @nogc
    {
        if (slot >= armed.length || key == 0)
            return Recorded.invalid;
        if (atomicLoad(armed[slot]) != key)
            return Recorded.ended;
        for (;;)
        {
            const previous = atomicLoad(signalled[slot]);
            if (previous >= key)
                return Recorded.duplicate;
            if (cas(&signalled[slot], previous, key))
                return Recorded.fresh;
        }
    }

    /// Signal from a thread other than the owner: record, mark the slot ready and ring the doorbell on the
    /// not-notified to notified transition. Never blocks.
    Status post(uint slot, ulong key) nothrow @nogc
    {
        atomicOp!"+="(writers, 1);
        scope (exit)
            atomicOp!"-="(writers, 1);
        if (atomicLoad(closed))
            return Status.cancelled;
        const recorded = record(slot, key);
        // A duplicate leaves delivery to the signal that recorded the wait first.
        if (recorded != Recorded.fresh)
            return statusOf(recorded);
        atomicOp!"|="(ready[slot / wordBits], 1UL << (slot % wordBits));
        if (cas(&notified, false, true))
        {
            ringDoorbell(bell);
            atomicOp!"+="(rings, 1);
        }
        return Status.ok;
    }

    /// Owner: whether a drain may find signals.
    bool pending() const nothrow @nogc
    {
        return atomicLoad(notified);
    }

    /// Owner: consume the doorbell and hand every slot marked ready to `deliver`. A signal that lands after the
    /// notified flag is cleared rings again, so none is lost between this drain and the loop's next sleep.
    void drain(scope void delegate(uint slot) @safe nothrow @nogc deliver) nothrow @nogc
    {
        if (!atomicLoad(notified))
            return;
        drainDoorbell(bell);
        atomicStore(notified, false);
        foreach (index, ref word; ready)
        {
            auto bits = atomicExchange(&word, 0UL);
            while (bits != 0)
            {
                import core.bitop : bsf;

                const bit = bsf(bits);
                bits &= bits - 1;
                deliver(cast(uint)(index * wordBits + bit));
            }
        }
    }

    /// Stop accepting signals, wait for signallers still using the doorbell, and close it. Owner threads have
    /// joined; a later `post` returns `Status.cancelled` without touching the closed descriptor.
    void close() nothrow @nogc
    {
        import flint.engine.reactor.sys.workers : yieldWorker;

        atomicStore(closed, true);
        while (atomicLoad(writers) != 0)
            yieldWorker();
        closeDoorbell(bell);
    }
}

/// Every owner's lane. A `RemoteWaker` keeps it alive, so a signal sent after the runtime is gone finds a closed
/// lane instead of freed memory or a reused descriptor.
package(flint.engine.reactor) final class RemoteWakes
{
    WakeLane[] lanes;

    this(uint owners)
    {
        lanes = new WakeLane[owners];
    }

    void close() nothrow @nogc
    {
        foreach (ref lane; lanes)
            lane.close();
    }
}

@("signals for a wait coalesce, and a stale or earlier key never matches or lowers a newer one")
unittest
{
    WakeLane lane;
    lane.armed = new shared(ulong)[2];
    lane.signalled = new shared(ulong)[2];
    lane.ready = new shared(ulong)[1];

    const first = lane.arm(1);
    assert(!lane.signalledNow(1));
    assert(lane.record(1, first) == Recorded.fresh);
    assert(lane.record(1, first) == Recorded.duplicate);
    assert(lane.signalledNow(1));
    lane.disarm(1);
    assert(lane.record(1, first) == Recorded.ended);

    const second = lane.arm(1);
    assert(second > first && !lane.signalledNow(1));
    // A late signal for the first wait cannot end the second.
    assert(lane.record(1, first) == Recorded.ended);
    assert(!lane.signalledNow(1));
    assert(lane.record(1, second) == Recorded.fresh && lane.signalledNow(1));
    assert(lane.record(0, second) == Recorded.ended);
    assert(lane.record(2, second) == Recorded.invalid);
    assert(lane.record(1, 0) == Recorded.invalid);
}
