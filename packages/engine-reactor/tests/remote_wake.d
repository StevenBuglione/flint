/// `RemoteWaker`: another thread ends one wait of a suspended task fiber without the owner's mailbox. The tests
/// cover the orderings that lose or duplicate wakes in naive designs: a signal before the waiter parks, during a
/// drain, twice, for an earlier wait of the same task, for a finished task, after the runtime stopped, while
/// every fiber slot is busy and the mailbox is full, against a racing deadline, and across two owners, on both
/// Linux backends.
module flint.engine.reactor.remote_wake_test;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.thread.osthread : Thread;
import flint.arena : Status;
import flint.conc : Deadline;
import flint.engine.reactor : Backend, Reactor, ReactorOptions, RemoteWaker, TaskContext;
import flint.engine.reactor.test_support : readinessBackend;

@safe:

private enum farMillis = 10_000;

private long monotonicNow() nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds;
}

private void pause() @trusted nothrow @nogc
{
    Thread.yield();
}

private Backend[] linuxBackends()
{
    return [Backend.automatic, readinessBackend];
}

/// One handle at a time, handed from the waiting fiber to a signalling thread. `round` publishes the handle;
/// `answered` publishes the signal's result.
private final class Exchange
{
    RemoteWaker handle;
    shared uint round;
    shared uint answered;
    shared int lastStatus = -1;
    shared bool done;

    void publish(RemoteWaker waker, uint number) nothrow @nogc
    {
        handle = waker;
        atomicStore(round, number);
    }

    /// Signal each published round once, until `done`.
    void signalRounds() nothrow @nogc
    {
        uint seen;
        while (!atomicLoad(done))
        {
            const current = atomicLoad(round);
            if (current == seen)
            {
                pause();
                continue;
            }
            seen = current;
            auto copy = handle;
            atomicStore(lastStatus, cast(int) copy.signal());
            atomicStore(answered, current);
        }
    }
}

private enum remoteRounds = 300;

private final class Waiter
{
    Exchange exchange;
    long elapsed;
    uint resumed;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        const started = monotonicNow();
        foreach (number; 1 .. remoteRounds + 1)
        {
            auto armed = owner.armRemoteWake();
            assert(armed.ok && armed.value.valid && armed.value.ownerCore == 0);
            exchange.publish(armed.value, number);
            assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
            ++resumed;
        }
        elapsed = monotonicNow() - started;
        atomicStore(exchange.done, true);
        owner.stop();
    }
}

@("a signal from another thread resumes the waiter on the owner's next pass, on each backend")
@system unittest
{
    foreach (backend; linuxBackends())
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 1;
        options.fiberPoolSize = 2;
        auto owner = Reactor.create(options);
        assert(owner.ok, owner.error.message);
        auto fixture = new Waiter;
        fixture.exchange = new Exchange;
        auto signaller = new Thread(&fixture.exchange.signalRounds);
        signaller.start();
        assert(owner.value.postStartup(0, &fixture.wait, TaskContext(1)).code == Status.ok);
        assert(owner.value.run().code == Status.ok);
        signaller.join();
        assert(fixture.resumed == remoteRounds);
        debug (remoteWakeTiming)
        {
            import core.stdc.stdio : printf;

            () @trusted {
                printf("remote wake: %u rounds in %lld ns\n", remoteRounds, fixture.elapsed);
            }();
        }
        // About 3 µs per round locally; without the doorbell the owner sleeps up to its 5 ms loop bound (about
        // 250 µs per round measured), and without any wake each round sleeps its 10 s deadline.
        assert(fixture.elapsed < remoteRounds * 100_000L, "a remote wake waited for a poll or deadline");
        const rings = owner.value.remoteWakeRings();
        assert(rings >= 1 && rings <= remoteRounds, "doorbell writes are not bounded by signals");
    }
}

private final class EarlySignal
{
    Exchange exchange;
    long elapsed;
    int status = -1;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        exchange.publish(owner.armRemoteWake().value, 1);
        // Stay on the fiber, without yielding, until the other thread has signalled.
        while (atomicLoad(exchange.answered) != 1)
            pause();
        status = atomicLoad(exchange.lastStatus);
        const started = monotonicNow();
        assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
        elapsed = monotonicNow() - started;
        atomicStore(exchange.done, true);
        owner.stop();
    }
}

@("a signal that arrives before the waiter parks ends its next yield at once")
@system unittest
{
    foreach (backend; linuxBackends())
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 1;
        options.fiberPoolSize = 1;
        auto owner = Reactor.create(options);
        assert(owner.ok);
        auto fixture = new EarlySignal;
        fixture.exchange = new Exchange;
        auto signaller = new Thread(&fixture.exchange.signalRounds);
        signaller.start();
        assert(owner.value.postStartup(0, &fixture.wait, TaskContext(1)).code == Status.ok);
        assert(owner.value.run().code == Status.ok);
        signaller.join();
        assert(fixture.status == Status.ok);
        assert(fixture.elapsed < 100_000_000, "a signal recorded before parking was lost");
    }
}

private final class StaleWait
{
    Exchange exchange;
    RemoteWaker finished;
    long elapsed;
    int staleStatus = -1;
    int finishedStatus = -1;
    int laterStatus = -1;

    void finishEarly() @safe nothrow @nogc
    {
        // Armed and never waited for: the task ends with the registration still armed.
        finished = Reactor.current().armRemoteWake().value;
    }

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        auto first = owner.armRemoteWake().value;
        assert(first.slot == finished.slot && first.generation != finished.generation);
        // The first wait ends at its deadline; its handle must not end the next one.
        assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        auto second = owner.armRemoteWake().value;
        assert(second.wait > first.wait);
        exchange.publish(first, 1);
        while (atomicLoad(exchange.answered) != 1)
            pause();
        staleStatus = atomicLoad(exchange.lastStatus);
        exchange.publish(finished, 2);
        while (atomicLoad(exchange.answered) != 2)
            pause();
        finishedStatus = atomicLoad(exchange.lastStatus);
        const started = monotonicNow();
        assert(owner.yieldUntil(Deadline.afterMillis(60)).code == Status.ok);
        elapsed = monotonicNow() - started;
        // The second wait ended with that yield: signalling it now is rejected too.
        exchange.publish(second, 3);
        while (atomicLoad(exchange.answered) != 3)
            pause();
        laterStatus = atomicLoad(exchange.lastStatus);
        atomicStore(exchange.done, true);
        owner.stop();
    }
}

@("a handle for an ended wait or a finished task is rejected and cannot end a newer wait in the same slot")
@system unittest
{
    ReactorOptions options;
    options.cores = 1;
    options.fiberPoolSize = 1;
    auto owner = Reactor.create(options);
    assert(owner.ok);
    auto fixture = new StaleWait;
    fixture.exchange = new Exchange;
    auto signaller = new Thread(&fixture.exchange.signalRounds);
    signaller.start();
    assert(owner.value.postStartup(0, &fixture.finishEarly, TaskContext(1)).code == Status.ok);
    assert(owner.value.postStartup(0, &fixture.wait, TaskContext(2)).code == Status.ok);
    assert(owner.value.run().code == Status.ok);
    signaller.join();
    assert(fixture.staleStatus == Status.notFound);
    assert(fixture.finishedStatus == Status.notFound);
    assert(fixture.laterStatus == Status.notFound);
    assert(fixture.elapsed >= 50_000_000, "a stale handle ended a newer wait");
    // Off the loop, after the runtime stopped, every handle is refused.
    auto late = fixture.finished;
    assert(late.signal() == Status.cancelled);
    RemoteWaker empty;
    assert(empty.signal() == Status.invalidArgument);
    // Off any fiber there is nothing to arm.
    assert(owner.value.armRemoteWake().error.code == Status.notFound);
}

private enum saturatedWaiters = 4;
private shared uint extrasRan;

private void extraTask() @safe nothrow @nogc
{
    atomicOp!"+="(extrasRan, 1);
}

private final class Saturated
{
    RemoteWaker[saturatedWaiters] handles;
    Reactor facade;
    uint extras;
    shared uint armed;
    shared uint resumed;
    shared uint queuedRan;
    long elapsed;
    long started;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        const self = cast(uint) owner.currentTask().value.requestId;
        handles[self] = owner.armRemoteWake().value;
        if (self == 0)
            facade = Reactor.current();
        if (atomicOp!"+="(armed, 1) == saturatedWaiters)
            started = monotonicNow();
        assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
        atomicOp!"+="(resumed, 1);
        finishIfDone();
    }

    void queued() @safe nothrow @nogc
    {
        // Runs only once a waiter's slot is free again.
        atomicOp!"+="(queuedRan, 1);
        finishIfDone();
    }

    /// The last of the waiters and the queued tasks stops the loop (one owner thread: no race between them).
    private void finishIfDone() @safe nothrow @nogc
    {
        if (atomicLoad(resumed) != saturatedWaiters || atomicLoad(queuedRan) != 2)
            return;
        elapsed = monotonicNow() - started;
        Reactor.current().stop();
    }

    void signalAll() nothrow @nogc
    {
        while (atomicLoad(armed) != saturatedWaiters)
            pause();
        // Fill the mailbox: no free fiber slot, so the owner does not dequeue it.
        while (facade.post(0, &extraTask).code == Status.ok)
            ++extras;
        assert(facade.post(0, &extraTask).code == Status.resourceExhausted);
        foreach (index; 0 .. saturatedWaiters)
        {
            auto copy = handles[index];
            assert(copy.signal() == Status.ok);
        }
    }
}

@("signals reach waiters while every fiber slot is busy and the mailbox is full")
@system unittest
{
    foreach (backend; linuxBackends())
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 1;
        options.fiberPoolSize = saturatedWaiters;
        options.mailboxCapacity = saturatedWaiters + 2;
        auto owner = Reactor.create(options);
        assert(owner.ok);
        auto fixture = new Saturated;
        foreach (index; 0 .. saturatedWaiters)
            assert(owner.value.postStartup(0, &fixture.wait, TaskContext(index)).code == Status.ok);
        // Two more tasks wait in the mailbox with no free fiber slot: the owner stops dequeuing it.
        assert(owner.value.postStartup(0, &fixture.queued, TaskContext(10)).code == Status.ok);
        assert(owner.value.postStartup(0, &fixture.queued, TaskContext(11)).code == Status.ok);
        auto signaller = new Thread(&fixture.signalAll);
        signaller.start();
        assert(owner.value.run().code == Status.ok);
        signaller.join();
        assert(atomicLoad(fixture.resumed) == saturatedWaiters && atomicLoad(fixture.queuedRan) == 2);
        assert(fixture.extras > 0, "the mailbox was never full");
        assert(fixture.elapsed < 1_000_000_000, "a waiter in a saturated owner waited for its deadline");
    }
}

private final class Duplicates
{
    Exchange exchange;
    uint yields;
    shared uint sent;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        exchange.publish(owner.armRemoteWake().value, 1);
        assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
        ++yields;
        // Later duplicates find the wait ended; they must not end this one.
        while (atomicLoad(sent) < 100)
            pause();
        assert(owner.yieldUntil(Deadline.afterMillis(30)).code == Status.ok);
        ++yields;
        owner.stop();
    }

    void burst() nothrow @nogc
    {
        while (atomicLoad(exchange.round) != 1)
            pause();
        auto copy = exchange.handle;
        foreach (_; 0 .. 100)
        {
            const status = copy.signal();
            assert(status == Status.ok || status == Status.notFound);
            atomicOp!"+="(sent, 1);
        }
    }
}

@("a burst of duplicate signals resumes the waiter once and rings the doorbell at most once per drain")
@system unittest
{
    ReactorOptions options;
    options.cores = 1;
    options.fiberPoolSize = 1;
    auto owner = Reactor.create(options);
    assert(owner.ok);
    auto fixture = new Duplicates;
    fixture.exchange = new Exchange;
    auto signaller = new Thread(&fixture.burst);
    signaller.start();
    const before = owner.value.taskResumptions();
    assert(owner.value.postStartup(0, &fixture.wait, TaskContext(1)).code == Status.ok);
    assert(owner.value.run().code == Status.ok);
    signaller.join();
    assert(fixture.yields == 2);
    // At most the start and one resumption per yield (a signal before parking needs none): never a duplicate.
    const resumptions = owner.value.taskResumptions() - before;
    assert(resumptions >= 2 && resumptions <= 3);
    assert(owner.value.remoteWakeRings() <= 3, "duplicates rang the doorbell for each signal");
}

private final class LocalSignal
{
    RemoteWaker handle;
    bool armed;
    int status = -1;
    bool resumed;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        handle = owner.armRemoteWake().value;
        armed = true;
        assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
        resumed = true;
        owner.stop();
    }

    long selfElapsed = -1;

    /// Signal its own armed wait before yielding: the yield must not park.
    void selfSignal() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        auto own = owner.armRemoteWake().value;
        assert(own.signal() == Status.ok);
        const started = monotonicNow();
        assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
        selfElapsed = monotonicNow() - started;
        // The wait ended with that yield.
        assert(own.signal() == Status.notFound);
    }

    void release() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        while (!armed)
            assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        status = handle.signal();
    }
}

@("a signal sent on the owner loop itself wakes the waiter without a doorbell write")
unittest
{
    foreach (backend; linuxBackends())
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 1;
        options.fiberPoolSize = 3;
        auto owner = Reactor.create(options);
        assert(owner.ok);
        auto fixture = new LocalSignal;
        assert(owner.value.postStartup(0, &fixture.wait, TaskContext(1)).code == Status.ok);
        assert(owner.value.postStartup(0, &fixture.release, TaskContext(2)).code == Status.ok);
        assert(owner.value.postStartup(0, &fixture.selfSignal, TaskContext(3)).code == Status.ok);
        const started = monotonicNow();
        assert(owner.value.run().code == Status.ok);
        assert(fixture.status == Status.ok && fixture.resumed);
        assert(fixture.selfElapsed >= 0 && fixture.selfElapsed < 100_000_000, "a signal before parking was lost");
        assert(monotonicNow() - started < 1_000_000_000);
        assert(owner.value.remoteWakeRings() == 0, "an owner-local signal made a system call");
    }
}

private enum raceRounds = 2_000;

private final class Race
{
    Exchange exchange;
    uint yields;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        foreach (number; 1 .. raceRounds + 1)
        {
            exchange.publish(owner.armRemoteWake().value, number);
            // A deadline about as long as the signal's delay: either may end the yield, never both.
            assert(owner.yieldUntil(Deadline(monotonicNow() + 20_000)).code == Status.ok);
            ++yields;
        }
        atomicStore(exchange.done, true);
        owner.stop();
    }
}

@("a deadline racing a signal ends the wait once, and the late signal cannot end the next wait")
@system unittest
{
    ReactorOptions options;
    options.cores = 1;
    options.fiberPoolSize = 1;
    auto owner = Reactor.create(options);
    assert(owner.ok);
    auto fixture = new Race;
    fixture.exchange = new Exchange;
    auto signaller = new Thread(&fixture.exchange.signalRounds);
    signaller.start();
    const before = owner.value.taskResumptions();
    assert(owner.value.postStartup(0, &fixture.wait, TaskContext(1)).code == Status.ok);
    assert(owner.value.run().code == Status.ok);
    signaller.join();
    assert(fixture.yields == raceRounds);
    // At most one resumption per yield plus the start; a signal before parking needs none.
    assert(owner.value.taskResumptions() - before <= raceRounds + 1, "a wait was resumed twice");
}

private enum pingRounds = 500;

/// One waiter per owner; each hands the turn to the other through the other's handle, so every signal crosses
/// owners and needs the doorbell.
private final class CrossOwner
{
    RemoteWaker[2] handles;
    shared uint ball;
    uint[2] turns;
    long elapsed;

    void play() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        const self = cast(uint) owner.currentTask().value.requestId;
        const other = 1 - self;
        const started = monotonicNow();
        while (turns[self] < pingRounds)
        {
            // Arm before checking the turn, so a signal sent after the check ends this yield.
            handles[self] = owner.armRemoteWake().value;
            if (atomicLoad(ball) == self)
            {
                ++turns[self];
                // The partner armed before it last read the ball, so the handle read after passing it is the one
                // its yield waits on; if it reads the ball after this, it takes the turn without yielding.
                atomicStore(ball, other);
                auto partner = handles[other];
                // A partner that has not armed yet has not started: it finds the ball on its first check.
                if (partner.valid)
                {
                    const status = partner.signal();
                    assert(status == Status.ok || status == Status.notFound);
                }
                continue;
            }
            assert(owner.yieldUntil(Deadline.afterMillis(farMillis)).code == Status.ok);
        }
        if (self == 1)
        {
            elapsed = monotonicNow() - started;
            owner.stop();
        }
    }
}

@("waiters on two owners hand a turn back and forth through remote wakes, on each backend")
unittest
{
    foreach (backend; linuxBackends())
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 2;
        options.fiberPoolSize = 1;
        auto owner = Reactor.create(options);
        if (!owner.ok && owner.error.code == Status.invalidArgument)
            return; // a single-CPU machine has no second owner
        assert(owner.ok);
        auto fixture = new CrossOwner;
        assert(owner.value.postStartup(0, &fixture.play, TaskContext(0)).code == Status.ok);
        assert(owner.value.postStartup(1, &fixture.play, TaskContext(1)).code == Status.ok);
        assert(owner.value.run().code == Status.ok);
        assert(fixture.turns[0] == pingRounds && fixture.turns[1] == pingRounds);
        assert(fixture.elapsed < pingRounds * 2_000_000L, "cross-owner handoff was paced by a poll");
        assert(owner.value.remoteWakeRings() >= 1);
    }
}

private final class StopDuringSignals
{
    Exchange exchange;
    shared ulong signals;

    void wait() @safe nothrow @nogc
    {
        auto owner = Reactor.current();
        foreach (number; 1 .. 50)
        {
            exchange.publish(owner.armRemoteWake().value, number);
            cast(void) owner.yieldUntil(Deadline.afterMillis(1));
        }
        owner.stop();
    }

    /// Signal the latest handle as fast as possible until the runtime refuses it.
    void hammer() nothrow @nogc
    {
        while (atomicLoad(exchange.round) == 0)
            pause();
        for (;;)
        {
            auto copy = exchange.handle;
            const status = copy.signal();
            atomicOp!"+="(signals, 1);
            if (status == Status.cancelled)
                return;
            assert(status == Status.ok || status == Status.notFound);
        }
    }
}

@("a thread signalling while the runtime stops gets cancelled, and the doorbell closes only after it")
@system unittest
{
    foreach (backend; linuxBackends())
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 1;
        options.fiberPoolSize = 1;
        auto owner = Reactor.create(options);
        assert(owner.ok);
        auto fixture = new StopDuringSignals;
        fixture.exchange = new Exchange;
        auto signaller = new Thread(&fixture.hammer);
        signaller.start();
        assert(owner.value.postStartup(0, &fixture.wait, TaskContext(1)).code == Status.ok);
        assert(owner.value.run().code == Status.ok);
        signaller.join();
        assert(atomicLoad(fixture.signals) > 0);
    }
}
