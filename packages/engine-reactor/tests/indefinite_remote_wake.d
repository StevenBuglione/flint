module flint.engine.reactor.indefinite_remote_wake_test;

import core.lifetime : move;
import flint.arena : Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.engine.reactor : Backend, Reactor, ReactorOptions, RemoteWaker, TaskContext;

@safe:

private ReactorOptions options()
{
    ReactorOptions result;
    result.cores = 1;
    result.fiberPoolSize = 2;
    version (linux)
        result.backend = Backend.epoll;
    return result;
}

private final class InterleavedWaits
{
    RemoteWaker waiting;
    bool firstResumed;
    bool secondRan;

    void first() nothrow @nogc
    {
        auto reactor = Reactor.current();
        assert(reactor.yieldForRemoteWake().code == Status.invalidArgument);
        auto abandoned = reactor.armRemoteWake();
        assert(abandoned.ok());
        assert(reactor.retireRemoteWake(abandoned.value).code == Status.ok);
        assert(abandoned.value.signal() == Status.notFound);

        auto replaced = reactor.armRemoteWake();
        auto armed = reactor.armRemoteWake();
        assert(replaced.ok() && armed.ok());
        assert(reactor.retireRemoteWake(replaced.value).code == Status.notFound);
        assert(replaced.value.signal() == Status.notFound);
        waiting = armed.value;
        assert(reactor.yieldForRemoteWake().code == Status.ok);
        assert(secondRan && waiting.signal() == Status.notFound);
        firstResumed = true;
        reactor.stop();
    }

    void second() nothrow @nogc
    {
        auto reactor = Reactor.current();
        assert(waiting.valid() && !firstResumed);
        assert(reactor.retireRemoteWake(waiting).code == Status.notFound);
        auto own = reactor.armRemoteWake();
        assert(own.ok() && own.value.signal() == Status.ok);
        assert(reactor.yieldForRemoteWake().code == Status.ok);
        secondRan = true;
        assert(waiting.signal() == Status.ok);
    }
}

@("remote wake retirement matches the active fiber and exact wait generation")
unittest
{
    auto reactor = Reactor.create(options());
    assert(reactor.ok());
    auto waits = new InterleavedWaits;
    assert(reactor.value.postStartup(0, &waits.first, TaskContext(1)).code == Status.ok);
    assert(reactor.value.postStartup(0, &waits.second, TaskContext(2)).code == Status.ok);
    assert(reactor.value.run().code == Status.ok);
    assert(waits.firstResumed && waits.secondRan);
}

private final class InterruptedWait
{
    CancelSource source;
    bool resumed;
    bool fallbackStopped;

    void wait() nothrow @nogc
    {
        auto reactor = Reactor.current();
        auto armed = reactor.armRemoteWake();
        assert(armed.ok());
        assert(reactor.yieldForRemoteWake().code == Status.cancelled);
        assert(armed.value.signal() == Status.notFound);
        resumed = true;
        reactor.stop();
    }

    void cancel() nothrow @nogc
    {
        auto reactor = Reactor.current();
        source.cancel();
        if (reactor.yieldUntil(Deadline.afterMillis(1000)).code == Status.ok)
        {
            fallbackStopped = true;
            reactor.stop();
        }
    }

    void stop() nothrow @nogc
    {
        Reactor.current().stop();
    }
}

@("task cancellation resumes a remote wait without a deadline")
unittest
{
    auto reactor = Reactor.create(options());
    assert(reactor.ok());
    auto waits = new InterruptedWait;
    auto created = CancelSource.create(Context.init, Deadline.none);
    assert(created.ok());
    move(created.value, waits.source);
    assert(reactor.value.postStartup(0, &waits.wait, TaskContext(1, waits.source.context())).code == Status.ok);
    assert(reactor.value.postStartup(0, &waits.cancel, TaskContext(2)).code == Status.ok);
    assert(reactor.value.run().code == Status.ok);
    assert(waits.resumed && !waits.fallbackStopped);
}

@("reactor shutdown resumes a remote wait without a deadline")
unittest
{
    auto reactor = Reactor.create(options());
    assert(reactor.ok());
    auto waits = new InterruptedWait;
    assert(reactor.value.postStartup(0, &waits.wait, TaskContext(1)).code == Status.ok);
    assert(reactor.value.postStartup(0, &waits.stop, TaskContext(2)).code == Status.ok);
    assert(reactor.value.run().code == Status.ok);
    assert(waits.resumed);
}
