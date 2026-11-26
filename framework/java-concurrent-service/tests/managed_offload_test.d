module flint.java.util.concurrent.managed_offload_test;

import core.atomic : atomicLoad, atomicStore;
import core.lifetime : move;
import core.memory : GC;
import core.thread : Thread;
import flint.arena : Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.conc.park : park, wakeAll;
import flint.conc.slot : ProcessSlot;
import flint.engine.reactor : Backend, Reactor, ReactorOptions, RemoteWaker, TaskContext;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.internal.executoradmissions : Admission, ExecutorAdmissions, ExecutorClaim;
import flint.java.util.concurrent.internal.executorrouting : ExecutorRoutes;
import flint.java.util.concurrent.internal.managedoffload : runManagedOffload;

@safe:

private ReactorOptions options(size_t fibers)
{
    ReactorOptions value;
    version (ServiceIoUring)
        value.backend = Backend.ioUring;
    else version (linux)
        value.backend = Backend.epoll;
    value.cores = 1;
    value.fiberPoolSize = cast(uint) fibers;
    value.offloadThreads = 1;
    value.offloadQueueCapacity = 2;
    return value;
}

private final class Payload
{
    size_t value;

    this(size_t value)
    {
        this.value = value;
    }
}

private final class AllocatingCommand : Runnable
{
    Payload payload;

    override void run()
    {
        assert(!Reactor.current().currentTask().ok());
        payload = new Payload(123);
        GC.collect();
    }
}

private final class ThrowingCommand : Runnable
{
    private Throwable failure;

    this(Throwable failure)
    {
        this.failure = failure;
    }

    override void run()
    {
        throw failure;
    }
}

private final class OutcomeFixture
{
    AllocatingCommand allocating;
    private Exception exception;
    private Error taskError;
    private ThrowingCommand throwsException;
    private ThrowingCommand throwsError;
    bool completed;

    this()
    {
        allocating = new AllocatingCommand;
        exception = new Exception("normal task failure");
        taskError = new Error("task error");
        throwsException = new ThrowingCommand(exception);
        throwsError = new ThrowingCommand(taskError);
    }

    void drive() nothrow @nogc
    {
        auto owner = Reactor.current();
        auto ok = runManagedOffload(allocating);
        assert(ok.error.code == Status.ok && ok.failure is null);
        assert(allocating.payload !is null && allocating.payload.value == 123);

        auto failed = runManagedOffload(throwsException);
        assert(failed.error.code == Status.ok && failed.failure is exception);
        auto errored = runManagedOffload(throwsError);
        assert(errored.error.code == Status.ioError && errored.failure is null);
        auto resumed = runManagedOffload(allocating);
        assert(resumed.error.code == Status.ok && resumed.failure is null);
        completed = true;
        owner.stop();
    }
}

@("the offload pool executes allocating commands and returns the exact task Exception")
unittest
{
    auto fixture = new OutcomeFixture;
    assert(runManagedOffload(null).error.code == Status.invalidArgument);
    auto inactive = runManagedOffload(fixture.allocating);
    assert(inactive.error.code == Status.notFound && inactive.failure is null);
    assert(fixture.allocating.payload is null);

    auto created = Reactor.create(options(1));
    assert(created.ok, created.error.message);
    assert(created.value.postStartup(0, &fixture.drive).code == Status.ok);
    assert(created.value.run().code == Status.ok);
    assert(fixture.completed);
}

@("an ordinary registered D thread cannot start reactor offload work")
@system unittest
{
    auto task = new AllocatingCommand;
    auto caller = new Thread({
        auto outcome = runManagedOffload(task);
        assert(outcome.error.code == Status.notFound && outcome.failure is null);
    }).start();
    caller.join();
    assert(task.payload is null);
}

private shared ProcessSlot!CancellationFixture cancellationFixture;

private void dispatchClaim() nothrow @nogc
{
    auto task = Reactor.current().currentTask();
    assert(task.ok);
    cancellationFixture.get().claim(task.value.requestId);
}

private final class CancellationFixture : Runnable
{
    private ExecutorAdmissions queue;
    private ExecutorRoutes routes;
    private Throwable failure;
    private CancelSource cancellation;
    private RemoteWaker started;
    private RemoteWaker interrupted;
    private shared bool controllerArmed;
    private shared uint release;
    private shared bool finished;
    private uint interruptCalls;
    private Payload payload;
    private bool returned;

    this()
    {
        queue = new ExecutorAdmissions(1);
        routes = new ExecutorRoutes(1);
        failure = new Exception("completed after cancellation");
        auto source = CancelSource.create(Context.init, Deadline.none());
        assert(source.ok);
        cancellation = move(source.value);
    }

    Context context() nothrow @nogc
    {
        return cancellation.context();
    }

    void close() nothrow @nogc
    {
        cancellation.close();
    }

    void admitFromNative(ref Reactor owner) @system
    {
        scope (failure)
            owner.stop();
        while (!atomicLoad(controllerArmed))
            Thread.yield();

        auto taskContext = context();
        assert(routes.admit(queue, this, (ulong token) => owner.post(0, &dispatchClaim,
                TaskContext(token, taskContext)).code == Status.ok) == Admission.accepted);
    }

    void cancel() nothrow @nogc
    {
        scope (exit)
        {
            atomicStore(release, 1u);
            wakeAll(release);
        }

        auto owner = Reactor.current();
        auto workStarted = owner.armRemoteWake();
        assert(workStarted.ok);
        started = workStarted.value;
        atomicStore(controllerArmed, true);
        assert(owner.yieldUntil(Deadline.afterMillis(5_000)).code == Status.ok);

        auto requestObserved = owner.armRemoteWake();
        assert(requestObserved.ok);
        interrupted = requestObserved.value;
        queue.shutdown();
        cancellation.cancel();
        assert(owner.yieldUntil(Deadline.afterMillis(5_000)).code == Status.ok);

        assert(interruptCalls == 1 && !returned && !atomicLoad(finished));
        assert(!queue.isTerminated());
    }

    void claim(ulong token) nothrow @nogc
    {
        auto owner = Reactor.current();
        ExecutorClaim active;
        assert(routes.takePermit(token) is queue && queue.tryStart(active) && active.command is this);
        scope (exit)
        {
            queue.retire(active);
            assert(queue.isTerminated());
            owner.stop();
        }

        auto outcome = runManagedOffload(active.command, &interrupt);
        returned = true;
        assert(outcome.error.code == Status.cancelled && outcome.failure is failure);
        assert(interruptCalls == 1 && atomicLoad(finished));
        assert(payload !is null && payload.value == 456);
        assert(!queue.isTerminated());
    }

    override void run()
    {
        assert(started.signal() == Status.ok);
        while (atomicLoad(release) == 0)
            park(release, 0, 1_000_000_000L);
        payload = new Payload(456);
        GC.collect();
        atomicStore(finished, true);
        throw failure;
    }

    private void interrupt() nothrow @nogc
    {
        ++interruptCalls;
        assert(interrupted.signal() == Status.ok);
    }

    bool completed() nothrow @nogc
    {
        return returned && queue.isTerminated();
    }
}

@("native scalar admission preserves task failure and retirement through cancellation")
@system unittest
{
    auto created = Reactor.create(options(2));
    assert(created.ok, created.error.message);
    auto fixture = new CancellationFixture;
    cancellationFixture.set(fixture);
    scope (exit)
    {
        cancellationFixture.set(null);
        fixture.close();
    }
    assert(created.value.postStartup(0, &fixture.cancel).code == Status.ok);
    auto producer = new Thread({ fixture.admitFromNative(created.value); }).start();
    assert(created.value.run().code == Status.ok);
    producer.join();
    assert(fixture.completed());
}

private shared ProcessSlot!ReuseFixture reuseFixture;

private void dispatchReuse() nothrow @nogc
{
    auto task = Reactor.current().currentTask();
    assert(task.ok);
    reuseFixture.get().dispatch(task.value.requestId);
}

private final class ReuseFixture
{
    private ExecutorRoutes routes;
    private ExecutorAdmissions oldQueue;
    private ExecutorAdmissions liveQueue;
    private AllocatingCommand withdrawn;
    private AllocatingCommand retained;
    private size_t dropped;
    private bool retired;

    this()
    {
        routes = new ExecutorRoutes(2);
        oldQueue = new ExecutorAdmissions(1);
        liveQueue = new ExecutorAdmissions(1);
        withdrawn = new AllocatingCommand;
        retained = new AllocatingCommand;
    }

    void post(ref Reactor owner)
    {
        assert(routes.admit(oldQueue, withdrawn, (ulong token) => owner.post(0, &dispatchReuse,
                TaskContext(token)).code == Status.ok) == Admission.accepted);
        auto pending = routes.shutdownNow(oldQueue);
        assert(pending.length == 1 && pending[0] is withdrawn && oldQueue.isTerminated());

        ulong liveToken;
        assert(routes.admit(liveQueue, retained, (ulong token) {
                liveToken = token;
                return owner.post(0, &dispatchReuse, TaskContext(token)).code == Status.ok;
            }) == Admission.accepted);
        assert(owner.post(0, &dispatchReuse, TaskContext(liveToken)).code == Status.ok);
        assert(owner.post(0, &dispatchReuse, TaskContext(liveToken)).code == Status.ok);

        auto overflowQueue = new ExecutorAdmissions(1);
        foreach (attempt; 0 .. 2)
        {
            Status rejection;
            assert(routes.admit(overflowQueue, withdrawn, (ulong token) {
                    rejection = owner.post(0, &dispatchReuse, TaskContext(token)).code;
                    return rejection == Status.ok;
                }) == Admission.unavailable);
            assert(rejection == Status.resourceExhausted);
        }
        assert(routes.shutdownNow(overflowQueue).length == 0 && overflowQueue.isTerminated());
        liveQueue.shutdown();
    }

    void dispatch(ulong token) nothrow @nogc
    {
        auto owner = Reactor.current();
        ExecutorClaim active;
        auto queue = routes.takePermit(token);
        if (queue is null || !queue.tryStart(active))
            ++dropped;
        else
        {
            assert(queue is liveQueue && active.command is retained);
            auto outcome = runManagedOffload(active.command);
            assert(outcome.error.code == Status.ok && outcome.failure is null);
            queue.retire(active);
            retired = true;
        }
        if (retired && dropped == 3)
            owner.stop();
    }

    bool complete()
    {
        return retired && dropped == 3 && withdrawn.payload is null && retained.payload !is null
            && retained.payload.value == 123 && liveQueue.isTerminated();
    }
}

@("the reactor drops stale scalars and rolls back routing when its mailbox is full")
unittest
{
    auto configured = options(2);
    configured.mailboxCapacity = 4;
    auto created = Reactor.create(configured);
    assert(created.ok, created.error.message);
    auto fixture = new ReuseFixture;
    reuseFixture.set(fixture);
    scope (exit)
        reuseFixture.set(null);
    fixture.post(created.value);
    assert(created.value.run().code == Status.ok);
    assert(fixture.complete());
}
