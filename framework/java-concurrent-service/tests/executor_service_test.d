module flint.java.util.concurrent.executor_service_test;

import core.atomic : atomicLoad, atomicStore;
import core.memory : GC;
import core.thread : Thread;
import flint.arena : Status;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.engine.reactor : Backend, ReactorOptions;
import flint.java.lang : NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.executor : Executor;
import flint.java.util.concurrent.executorservice : ExecutorService, OffloadExecutorService;
import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;
import std.exception : assertThrown;

@safe:

private ReactorOptions options()
{
    ReactorOptions result;
    version (ServiceIoUring)
        result.backend = Backend.ioUring;
    else version (linux)
        result.backend = Backend.epoll;
    result.cores = 1;
    result.fiberPoolSize = 2;
    result.mailboxCapacity = 4;
    result.offloadThreads = 1;
    return result;
}

private final class Work : Runnable
{
    uint[] data;
    private Exception failure;

    this(Exception failure = null)
    {
        this.failure = failure;
    }

    override void run()
    {
        data = new uint[2];
        data[1] = 42;
        GC.collect();
        if (failure !is null)
            throw failure;
    }
}

@("public executor drains accepted work and reports the original failure")
unittest
{
    auto failure = new Exception("worker failure");
    auto task = new Work(failure);
    auto later = new Work;
    Exception observed;
    Runnable failedCommand;
    auto host = new OffloadExecutorService(2, options(), (command, status, outcome) {
        assert(status.code == Status.ok);
        failedCommand = command;
        observed = outcome;
    });
    ExecutorService service = host;
    Executor executor = service;
    assertThrown!NullPointerException(executor.execute(cast(Runnable) null));
    executor.execute(task);
    executor.execute(later);
    assertThrown!RejectedExecutionException(executor.execute(new Work));
    service.shutdown();
    assert(service.isShutdown() && !service.isTerminated());
    assertThrown!RejectedExecutionException(executor.execute(new Work));
    assert(host.run().code == Status.ok);
    assert(service.isTerminated() && task.data[1] == 42 && later.data[1] == 42);
    assert(failedCommand is task && observed is failure);
}

@("public immediate shutdown returns original pending tasks in order")
unittest
{
    auto host = new OffloadExecutorService(2, options());
    ExecutorService service = host;
    auto first = new Work;
    auto second = new Work;
    service.execute(first);
    service.execute(second);
    auto pending = service.shutdownNow();
    assert(pending.size() == 2 && pending.get(0) is first && pending.get(1) is second);
    assert(service.shutdownNow().isEmpty());
    assert(service.isShutdown() && service.isTerminated());
    assert(host.run().code == Status.ok);
    assert(first.data is null && second.data is null);
}

private interface WorkMarker
{
    int id() const pure nothrow @nogc;
}

private final class MarkedWork : WorkMarker, Runnable
{
    override int id() const pure nothrow @nogc
    {
        return 7;
    }

    override void run()
    {
        assert(0, "pending work must not start");
    }
}

@("immediate shutdown preserves a secondary Runnable reference through the returned list")
unittest
{
    ExecutorService service = new OffloadExecutorService(1, options());
    auto work = new MarkedWork;
    WorkMarker marker = work;
    Runnable command = work;
    service.execute(command);

    auto pending = service.shutdownNow();
    assert(pending.size() == 1);
    auto returned = pending.get(0);
    assert(returned is command && cast(WorkMarker) returned is marker);
    assert((cast(WorkMarker) returned).id() == 7);

    auto iterator = pending.iterator();
    assert(iterator.hasNext() && iterator.next() is command && !iterator.hasNext());
    auto copy = pending.toArray();
    assert(copy.length == 1 && copy[0] is command);
}

@("a stopped reactor revokes undelivered routes and preserves the pending snapshot")
unittest
{
    auto host = new OffloadExecutorService(2, options());
    ExecutorService service = host;
    auto first = new Work;
    auto second = new Work;
    service.execute(first);
    service.execute(second);
    host.requestStop();
    assert(host.run().code == Status.conflict);
    assert(service.isShutdown() && service.isTerminated());
    auto pending = service.shutdownNow();
    assert(pending.size() == 2 && pending.get(0) is first && pending.get(1) is second);
    assert(first.data is null && second.data is null);
}

private final class BlockingWork : Runnable
{
    shared uint started;
    shared uint released;

    override void run()
    {
        atomicStore(started, 1u);
        wakeAll(started);
        while (atomicLoad(released) == 0)
            park(released, 0, 100_000_000L);
    }

    void release() nothrow @nogc
    {
        atomicStore(released, 1u);
        wakeAll(released);
    }
}

private bool before(Deadline deadline) nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds < deadline.monotonicNanoseconds;
}

private void waitForStart(BlockingWork active)
{
    const deadline = Deadline.afterMillis(5_000);
    while (atomicLoad(active.started) == 0 && before(deadline))
        park(active.started, 0, 100_000_000L);
    assert(atomicLoad(active.started) == 1);
}

@("stopping a running reactor retires active offload and returns never-started work")
@system unittest
{
    auto reactorOptions = options();
    reactorOptions.fiberPoolSize = 1;
    auto host = new OffloadExecutorService(2, reactorOptions);
    ExecutorService service = host;
    auto active = new BlockingWork;
    auto queued = new Work;
    service.execute(active);

    Status result;
    auto driver = new Thread({ result = host.run().code; }).start();
    scope (failure)
    {
        host.requestStop();
        active.release();
        driver.join(false);
    }

    waitForStart(active);
    service.execute(queued);
    host.requestStop();
    assert(!service.isTerminated());

    active.release();
    driver.join();
    assert(result == Status.ok && service.isTerminated());
    auto pending = service.shutdownNow();
    assert(pending.size() == 1 && pending.get(0) is queued);
    assert(queued.data is null && service.shutdownNow().isEmpty());
}

@("immediate shutdown returns work already dispatched to the native queue without starting it")
@system unittest
{
    auto reactorOptions = options();
    reactorOptions.mailboxCapacity = 1;
    reactorOptions.offloadQueueCapacity = 2;
    auto host = new OffloadExecutorService(3, reactorOptions);
    ExecutorService service = host;
    auto active = new BlockingWork;
    auto waitingForWorker = new Work;
    auto waitingForFiber = new Work;
    service.execute(active);

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        host.requestStop();
        active.release();
        driver.join();
    }

    waitForStart(active);
    service.execute(waitingForWorker);
    const deadline = Deadline.afterMillis(5_000);
    for (;;)
    {
        try
        {
            // The one-entry mailbox has room only after the owner takes the preceding task.
            service.execute(waitingForFiber);
            break;
        }
        catch (RejectedExecutionException rejected)
        {
            assert(before(deadline));
            Thread.yield();
        }
    }

    auto pending = service.shutdownNow();
    assert(pending.size() == 2 && pending.get(0) is waitingForWorker && pending.get(1) is waitingForFiber);
    assert(!service.isTerminated());
}
