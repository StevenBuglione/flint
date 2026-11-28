module flint.java.util.concurrent.executor_service_test;

import core.atomic : atomicLoad, atomicStore;
import core.memory : GC;
import core.thread : Thread;
import flint.arena : Status;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.engine.reactor : Backend, ReactorOptions;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util : ArrayList, Collection;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.executor : Executor;
import flint.java.util.concurrent.executorservice : ExecutorService, OffloadExecutorService;
import flint.java.util.concurrent.future : Future;
import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;
import flint.java.util.concurrent.timeoutexception : TimeoutException;
import std.exception : assertThrown;

@safe:

private ReactorOptions options(uint offloadThreads = 1)
{
    ReactorOptions result;
    version (ServiceIoUring)
        result.backend = Backend.ioUring;
    else version (linux)
        result.backend = Backend.epoll;
    result.cores = 1;
    result.fiberPoolSize = 2;
    result.mailboxCapacity = 4;
    result.offloadThreads = offloadThreads;
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

private final class Doubling : Callable!int
{
    private int input;

    this(int input)
    {
        this.input = input;
    }

    override int call()
    {
        return input * 2;
    }
}

private final class FailingCall : Callable!int
{
    override int call()
    {
        throw new Exception("callable failure");
    }
}

@("submit returns owned futures for Callable, Runnable with a result, and Runnable")
unittest
{
    auto host = new OffloadExecutorService(3, options());
    ExecutorService service = host;
    Future!int doubled = service.submit(new Doubling(21));
    Future!string labelled = service.submit(new Work, "done");
    Future!Object empty = service.submit(new Work);
    assert(!doubled.isDone() && !labelled.isDone() && !empty.isDone());

    service.shutdown();
    assert(host.run().code == Status.ok);
    assert(doubled.get() == 42 && labelled.get() == "done" && empty.get() is null);
    assert(doubled.isDone() && labelled.isDone() && empty.isDone());
}

@("submit publishes a task's failure through its future")
unittest
{
    auto host = new OffloadExecutorService(2, options());
    ExecutorService service = host;
    Future!int failed = service.submit(new FailingCall);
    Future!Object runner = service.submit(new Work(new Exception("runner failure")));

    service.shutdown();
    assert(host.run().code == Status.ok);
    ExecutionException caught;
    try
        failed.get();
    catch (ExecutionException failure)
        caught = failure;
    assert(caught !is null);
    auto cause = caught.getCause();
    assert((cast(Exception) cause) !is null && (cast(Exception) cause).msg == "callable failure");
    assertThrown!ExecutionException(runner.get());
}

@("a submitted future can be cancelled before its task starts")
unittest
{
    auto host = new OffloadExecutorService(1, options());
    ExecutorService service = host;
    auto future = service.submit(new Doubling(1));
    assert(!future.isDone());
    assert(future.cancel(true));
    assert(future.isCancelled());

    service.shutdown();
    assert(host.run().code == Status.ok);
    assertThrown!CancellationException(future.get());
    assert(future.isDone() && future.isCancelled());
}

@("submit rejects a null task and a task after shutdown")
unittest
{
    auto service = new OffloadExecutorService(1, options());
    assertThrown!NullPointerException(service.submit(cast(Callable!int) null));
    assertThrown!NullPointerException(service.submit(cast(Runnable) null));
    service.shutdownNow();
    assertThrown!RejectedExecutionException(service.submit(new Doubling(1)));
    assertThrown!RejectedExecutionException(service.submit(new Work));
}

private final class BlockingCall : Callable!int
{
    shared uint started;
    shared uint released;

    override int call()
    {
        atomicStore(started, 1u);
        wakeAll(started);
        while (atomicLoad(released) == 0)
            park(released, 0, 100_000_000L);
        return 9;
    }

    void release() nothrow @nogc
    {
        atomicStore(released, 1u);
        wakeAll(released);
    }
}

private ArrayList!(Callable!int) callables(Callable!int[] tasks...)
{
    auto result = new ArrayList!(Callable!int)();
    foreach (task; tasks)
        result.add(task);
    return result;
}

@("invokeAll runs every task and returns futures in iteration order")
@system unittest
{
    auto host = new OffloadExecutorService(3, options());
    ExecutorService service = host;
    auto tasks = callables(new Doubling(21), new FailingCall, new Doubling(2));

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        host.requestStop();
        driver.join();
    }

    auto futures = service.invokeAll(tasks);
    assert(futures.size() == 3);
    assert(!(futures.get(0) is null) && !(futures.get(1) is null) && !(futures.get(2) is null));
    assert(futures.get(0).get() == 42 && futures.get(2).get() == 4);
    assertThrown!ExecutionException(futures.get(1).get());
    assert(futures.get(0).isDone() && futures.get(1).isDone() && futures.get(2).isDone());
}

@("timed invokeAll cancels unfinished futures and does not throw TimeoutException")
@system unittest
{
    auto host = new OffloadExecutorService(2, options());
    ExecutorService service = host;
    auto blocked = new BlockingCall;
    auto tasks = callables(blocked, new Doubling(3));

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        host.requestStop();
        blocked.release();
        driver.join();
    }

    auto started = Deadline.afterMillis(0).monotonicNanoseconds;
    auto futures = service.invokeAll(tasks, 50, TimeUnit.MILLISECONDS);
    auto elapsed = Deadline.afterMillis(0).monotonicNanoseconds - started;

    assert(elapsed >= 50_000_000L);
    assert(futures.size() == 2);
    assert(futures.get(0).isCancelled() && futures.get(1).isDone());
    assertThrown!CancellationException(futures.get(0).get());
}

@("a nonpositive invokeAll timeout returns unstarted cancelled futures")
unittest
{
    ExecutorService service = new OffloadExecutorService(1, options());
    auto task = new Doubling(1);
    auto futures = service.invokeAll(callables(task), -1, TimeUnit.SECONDS);
    assert(futures.size() == 1);
    assert(futures.get(0).isCancelled() && futures.get(0).isDone());
}

@("invokeAll takes an empty collection and rejects a null one")
unittest
{
    ExecutorService service = new OffloadExecutorService(1, options());
    assert(service.invokeAll(new ArrayList!(Callable!int)()).isEmpty());
    assertThrown!NullPointerException(service.invokeAll(cast(Collection!(Callable!int)) null));
    assertThrown!NullPointerException(service.invokeAll(cast(Collection!(Callable!int)) null, 1, TimeUnit.SECONDS));
}

@("invokeAny returns the successful task's result and cancels the failures")
@system unittest
{
    auto host = new OffloadExecutorService(3, options());
    ExecutorService service = host;
    auto tasks = callables(new FailingCall, new Doubling(21), new FailingCall);

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        host.requestStop();
        driver.join();
    }

    assert(service.invokeAny(tasks) == 42);
}

@("invokeAny returns a fast success while an earlier task is still blocked")
@system unittest
{
    auto host = new OffloadExecutorService(2, options(2));
    ExecutorService service = host;
    auto blocked = new BlockingCall;
    auto tasks = callables(blocked, new Doubling(3));

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        blocked.release();
        host.requestStop();
        driver.join();
    }

    const started = Deadline.afterMillis(0).monotonicNanoseconds;
    assert(service.invokeAny(tasks) == 6);
    const elapsed = Deadline.afterMillis(0).monotonicNanoseconds - started;
    assert(elapsed < 5_000_000_000L);
    assert(atomicLoad(blocked.started) == 1);
}

@("invokeAny reports the last failure when every task fails")
@system unittest
{
    auto host = new OffloadExecutorService(2, options());
    ExecutorService service = host;
    auto tasks = callables(new FailingCall, new FailingCall);

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        host.requestStop();
        driver.join();
    }

    assertThrown!ExecutionException(service.invokeAny(tasks));
}

@("timed invokeAny returns a success before the deadline")
@system unittest
{
    auto host = new OffloadExecutorService(2, options());
    ExecutorService service = host;
    auto tasks = callables(new FailingCall, new Doubling(5));

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        host.requestStop();
        driver.join();
    }

    assert(service.invokeAny(tasks, 5, TimeUnit.SECONDS) == 10);
}

@("timed invokeAny throws TimeoutException and cancels the unfinished tasks")
@system unittest
{
    auto host = new OffloadExecutorService(1, options());
    ExecutorService service = host;
    auto blocked = new BlockingCall;
    auto tasks = callables(blocked);

    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        blocked.release();
        host.requestStop();
        driver.join();
    }

    const started = Deadline.afterMillis(0).monotonicNanoseconds;
    assertThrown!TimeoutException(service.invokeAny(tasks, 50, TimeUnit.MILLISECONDS));
    const elapsed = Deadline.afterMillis(0).monotonicNanoseconds - started;
    assert(elapsed >= 50_000_000L);
}

@("invokeAny rejects empty and null task collections and a null element")
unittest
{
    ExecutorService service = new OffloadExecutorService(1, options());
    assertThrown!IllegalArgumentException(service.invokeAny(new ArrayList!(Callable!int)()));
    assertThrown!IllegalArgumentException(service.invokeAny(new ArrayList!(Callable!int)(), 1, TimeUnit.SECONDS));
    assertThrown!NullPointerException(service.invokeAny(cast(Collection!(Callable!int)) null));
    assertThrown!NullPointerException(service.invokeAny(cast(Collection!(Callable!int)) null, 1, TimeUnit.SECONDS));
    assertThrown!NullPointerException(service.invokeAny(callables(cast(Callable!int) null)));
}

@("invokeAny wakes and throws when another thread interrupts the waiter")
@system unittest
{
    import flint.java.lang.interruptedexception : InterruptedException;
    import flint.java.lang.thread : JavaThread = Thread;

    auto host = new OffloadExecutorService(1, options());
    ExecutorService service = host;
    auto blocked = new BlockingCall;
    auto tasks = callables(blocked);
    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        blocked.release();
        service.shutdownNow();
        driver.join();
    }

    __gshared JavaThread waiter;
    __gshared bool started;
    __gshared bool interrupted;
    __gshared bool flagCleared;
    auto worker = new Thread({
        auto self = JavaThread.currentThread();
        waiter = self;
        atomicStore(started, true);
        try
            service.invokeAny(tasks);
        catch (InterruptedException)
        {
            interrupted = true;
            flagCleared = !self.isInterrupted();
        }
    });
    worker.start();
    while (!atomicLoad(started))
        Thread.yield();
    while (atomicLoad(blocked.started) == 0)
        Thread.yield();
    waiter.interrupt();
    worker.join();

    assert(interrupted, "the waiter must observe the interrupt instead of waiting for the task");
    assert(flagCleared, "Java clears the flag when invokeAny throws");
}

@("awaitTermination reports termination after the driven reactor exits")
@system unittest
{
    auto host = new OffloadExecutorService(1, options());
    ExecutorService service = host;
    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    service.shutdown();
    assert(service.awaitTermination(5, TimeUnit.SECONDS));
    assert(service.isTerminated());
    driver.join();
}

@("awaitTermination times out while the service is still running")
@system unittest
{
    auto host = new OffloadExecutorService(1, options());
    ExecutorService service = host;
    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        service.shutdownNow();
        driver.join();
    }

    const started = Deadline.afterMillis(0).monotonicNanoseconds;
    assert(!service.awaitTermination(50, TimeUnit.MILLISECONDS));
    const elapsed = Deadline.afterMillis(0).monotonicNanoseconds - started;
    assert(elapsed >= 50_000_000L);
    assert(!service.isShutdown());
}

@("awaitTermination returns at once for a terminated service")
unittest
{
    auto service = new OffloadExecutorService(1, options());
    service.shutdownNow();
    assert(service.isTerminated());
    assert(service.awaitTermination(0, TimeUnit.NANOSECONDS));
    assert(service.awaitTermination(-1, TimeUnit.SECONDS));
}

@("awaitTermination throws InterruptedException when the calling thread is already interrupted")
unittest
{
    import flint.java.lang.interruptedexception : InterruptedException;
    import flint.java.lang.thread : JavaThread = Thread;

    auto service = new OffloadExecutorService(1, options());
    JavaThread.currentThread().interrupt();
    try
    {
        service.awaitTermination(1, TimeUnit.SECONDS);
        assert(false, "awaitTermination must throw InterruptedException");
    }
    catch (InterruptedException)
    {
    }
    assert(!JavaThread.currentThread().isInterrupted());
    service.shutdownNow();
}

@("awaitTermination wakes and throws when another thread interrupts the waiter")
@system unittest
{
    import flint.java.lang.interruptedexception : InterruptedException;
    import flint.java.lang.thread : JavaThread = Thread;

    auto host = new OffloadExecutorService(1, options());
    ExecutorService service = host;
    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    scope (exit)
    {
        service.shutdownNow();
        driver.join();
    }

    __gshared JavaThread waiter;
    __gshared bool started;
    __gshared bool interrupted;
    __gshared bool flagCleared;
    auto worker = new Thread({
        auto self = JavaThread.currentThread();
        waiter = self;
        atomicStore(started, true);
        try
            service.awaitTermination(10, TimeUnit.SECONDS);
        catch (InterruptedException)
        {
            interrupted = true;
            flagCleared = !self.isInterrupted();
        }
    });
    worker.start();
    while (!atomicLoad(started))
        Thread.yield();
    waiter.interrupt();
    worker.join();

    assert(interrupted, "the waiter must observe the interrupt instead of the timeout");
    assert(flagCleared, "Java clears the flag when awaitTermination throws");
    assert(!service.isTerminated());
}

@("close returns for an already terminated service")
unittest
{
    auto service = new OffloadExecutorService(1, options());
    service.shutdownNow();
    assert(service.isTerminated());
    service.close();
}

@("close shuts down a running service and returns after termination")
@system unittest
{
    auto host = new OffloadExecutorService(1, options());
    auto driver = new Thread({ assert(host.run().code == Status.ok); }).start();
    host.close();
    assert(host.isShutdown() && host.isTerminated());
    driver.join();
}

@("close escalates an interrupt to shutdownNow once and restores the flag")
unittest
{
    import flint.java.lang.thread : JavaThread = Thread;

    auto service = new OffloadExecutorService(1, options());
    auto task = new Work;
    service.execute(task);
    JavaThread.currentThread().interrupt();
    service.close();
    assert(service.isShutdown() && service.isTerminated());
    assert(JavaThread.currentThread().isInterrupted());
    assert(JavaThread.interrupted());
    assert(task.data is null);
}
