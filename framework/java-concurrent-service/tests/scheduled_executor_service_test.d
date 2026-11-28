module flint.java.util.concurrent.scheduled_executor_service_test;

import core.atomic : atomicLoad, atomicStore;
import flint.conc : Deadline;
import flint.conc.wait : waitUntil;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.future : FutureState;
import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.executorservice : ExecutorService;
import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;
import flint.java.util.concurrent.scheduledexecutorservice : OffloadScheduledExecutorService, ScheduledExecutorService;
import flint.java.util.concurrent.scheduledfuture : RunnableScheduledFuture, ScheduledFuture;
import flint.java.util.concurrent.timeoutexception : TimeoutException;
import std.exception : assertThrown;

@safe:

private final class Value : Callable!int
{
    private int value;

    this(int value)
    {
        this.value = value;
    }

    override int call()
    {
        return value;
    }
}

private final class Flag : Runnable
{
    private shared bool ran;

    override void run()
    {
        atomicStore(ran, true);
    }

    bool completed() nothrow @nogc
    {
        return atomicLoad(ran);
    }
}

private void awaitTermination(ExecutorService service)
{
    const deadline = Deadline.afterMillis(2_000).monotonicNanoseconds;
    while (!service.isTerminated())
    {
        assert(Deadline.afterMillis(0).monotonicNanoseconds < deadline, "executor did not terminate");
        waitUntil(Deadline(Deadline.afterMillis(0).monotonicNanoseconds + 1_000_000));
    }
}

@("one-shot schedule returns the callable's value after its delay")
unittest
{
    ScheduledExecutorService service = new OffloadScheduledExecutorService;
    auto future = service.schedule(new Value(42), 10, TimeUnit.MILLISECONDS);
    assert(!future.isCancelled);
    assert(future.get(5, TimeUnit.SECONDS) == 42);
    assert(future.isDone);
    assert(future.getDelay(TimeUnit.MILLISECONDS) <= 0);
    service.shutdown();
    awaitTermination(service);
    assert(service.isShutdown);
}

@("the Runnable form completes with Java's null result")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    auto flag = new Flag;
    ScheduledFuture!Object future = service.schedule(flag, 0, TimeUnit.MILLISECONDS);
    assert(future.get(5, TimeUnit.SECONDS) is null);
    assert(flag.completed());
    assert(future.isDone);
    service.shutdownNow();
    awaitTermination(service);
}

@("a null task is rejected as Java does")
unittest
{
    ScheduledExecutorService service = new OffloadScheduledExecutorService;
    assertThrown!NullPointerException(service.schedule(cast(Callable!int) null, 1, TimeUnit.SECONDS));
    assertThrown!NullPointerException(service.schedule(cast(Runnable) null, 1, TimeUnit.SECONDS));
    service.shutdownNow();
}

@("earlier deadlines order before later ones")
unittest
{
    ScheduledExecutorService service = new OffloadScheduledExecutorService;
    auto later = service.schedule(new Value(2), 2_000, TimeUnit.MILLISECONDS);
    auto earlier = service.schedule(new Value(1), 1_000, TimeUnit.MILLISECONDS);
    Delayed laterDelay = later;
    Delayed earlierDelay = earlier;
    assert(later.compareTo(earlier) > 0);
    assert(earlier.compareTo(later) < 0);
    assert(earlier.compareTo(earlier) == 0);
    assert(laterDelay.getDelay(TimeUnit.NANOSECONDS) > earlierDelay.getDelay(TimeUnit.NANOSECONDS));
    service.shutdownNow();
    awaitTermination(service);
}

@("shutdownNow cancels and returns the pending task")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    ScheduledFuture!int future = service.schedule(new Value(7), 1_000, TimeUnit.MILLISECONDS);
    auto pending = service.shutdownNow();
    assert(pending.size() == 1);
    assert(pending.get(0) is cast(Runnable) future);
    assert(future.isCancelled);
    assert(service.isShutdown);
    awaitTermination(service);
    assert(service.isTerminated);
}

@("execute after shutdown is rejected")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    service.shutdown();
    awaitTermination(service);
    assertThrown!RejectedExecutionException(service.schedule(new Value(1), 0, TimeUnit.MILLISECONDS));
}

@("inherited submit runs immediately through execute")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    ExecutorService executor = service;
    auto future = executor.submit(new Value(9));
    assert(future.get(5, TimeUnit.SECONDS) == 9);
    service.shutdown();
    awaitTermination(service);
}

private final class Counter : Runnable
{
    private shared uint runs;

    override void run()
    {
        atomicStore(runs, atomicLoad(runs) + 1);
    }

    uint count() nothrow @nogc
    {
        return atomicLoad(runs);
    }
}

private final class FailingPeriodic : Runnable
{
    private shared uint runs;
    private Exception failure;

    this(Exception failure)
    {
        this.failure = failure;
    }

    override void run()
    {
        atomicStore(runs, atomicLoad(runs) + 1);
        throw failure;
    }

    uint count() nothrow @nogc
    {
        return atomicLoad(runs);
    }

    Exception cause() nothrow @nogc
    {
        return failure;
    }
}

private bool waitForCount(Counter counter, uint target)
{
    const deadline = Deadline.afterMillis(2_000).monotonicNanoseconds;
    while (counter.count() < target)
    {
        if (Deadline.afterMillis(0).monotonicNanoseconds >= deadline)
            return false;
        waitUntil(Deadline(Deadline.afterMillis(0).monotonicNanoseconds + 1_000_000));
    }
    return true;
}

@("fixed rate repeats until cancelled and its future reports cancellation")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    auto counter = new Counter;
    ScheduledFuture!Object future = service.scheduleAtFixedRate(counter, 0, 5, TimeUnit.MILLISECONDS);
    assert(waitForCount(counter, 3), "fixed-rate task did not repeat");

    assert(future.cancel(false));
    assert(future.isCancelled && future.isDone);
    assertThrown!CancellationException(future.get());

    service.shutdown();
    awaitTermination(service);
    const finalCount = counter.count();
    assert(finalCount >= 3);
    waitUntil(Deadline(Deadline.afterMillis(0).monotonicNanoseconds + 20_000_000));
    assert(counter.count() == finalCount, "a cancelled fixed-rate task ran again");
}

@("fixed delay repeats with the delay between runs and stops on cancel")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    auto counter = new Counter;
    ScheduledFuture!Object future = service.scheduleWithFixedDelay(counter, 0, 2, TimeUnit.MILLISECONDS);
    assert(waitForCount(counter, 3), "fixed-delay task did not repeat");

    assert(future.cancel(false));
    service.shutdown();
    awaitTermination(service);
    assert(counter.count() >= 3);
    assert(future.isCancelled);
}

@("a periodic task that throws completes its future exceptionally and stops")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    auto burst = new Exception("periodic failure");
    auto failing = new FailingPeriodic(burst);
    ScheduledFuture!Object future = service.scheduleAtFixedRate(failing, 0, 2, TimeUnit.MILLISECONDS);

    const deadline = Deadline.afterMillis(2_000).monotonicNanoseconds;
    while (!future.isDone)
    {
        assert(Deadline.afterMillis(0).monotonicNanoseconds < deadline, "periodic failure was not published");
        waitUntil(Deadline(Deadline.afterMillis(0).monotonicNanoseconds + 1_000_000));
    }

    assert(!future.isCancelled);
    assert(failing.count() == 1);
    ExecutionException caught;
    try
        future.get();
    catch (ExecutionException failure)
        caught = failure;
    assert(caught !is null && caught.getCause() is burst);
    assert(future.state() == FutureState.FAILED);

    service.shutdown();
    awaitTermination(service);
    assert(failing.count() == 1, "a failed periodic task ran again");
}

@("the timed periodic get reports TimeoutException while the task repeats")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    auto counter = new Counter;
    ScheduledFuture!Object future = service.scheduleAtFixedRate(counter, 0, 10, TimeUnit.MILLISECONDS);
    assertThrown!TimeoutException(future.get(1, TimeUnit.MILLISECONDS));
    assert(!future.isDone);
    service.shutdownNow();
    awaitTermination(service);
}

@("shutdown cancels a pending periodic task and lets the service terminate")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    auto counter = new Counter;
    ScheduledFuture!Object future = service.scheduleAtFixedRate(counter, 10_000, 10_000, TimeUnit.MILLISECONDS);
    assert(!future.isDone);
    service.shutdown();
    awaitTermination(service);
    assert(future.isCancelled && future.isDone);
    assert(counter.count() == 0);
    assertThrown!CancellationException(future.get());
}

@("periodic forms validate their arguments as Java does")
unittest
{
    ScheduledExecutorService service = new OffloadScheduledExecutorService;
    assertThrown!NullPointerException(service.scheduleAtFixedRate(cast(Runnable) null, 0, 1, TimeUnit.SECONDS));
    assertThrown!NullPointerException(service.scheduleWithFixedDelay(cast(Runnable) null, 0, 1, TimeUnit.SECONDS));
    assertThrown!IllegalArgumentException(service.scheduleAtFixedRate(new Counter, 0, 0, TimeUnit.SECONDS));
    assertThrown!IllegalArgumentException(service.scheduleAtFixedRate(new Counter, 0, -1, TimeUnit.SECONDS));
    assertThrown!IllegalArgumentException(service.scheduleWithFixedDelay(new Counter, 0, 0, TimeUnit.SECONDS));
    assertThrown!IllegalArgumentException(service.scheduleWithFixedDelay(new Counter, 0, -1, TimeUnit.SECONDS));
    service.shutdownNow();
}

@("one-shot and periodic futures report isPeriodic")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    ScheduledFuture!int oneShot = service.schedule(new Value(1), 0, TimeUnit.MILLISECONDS);
    ScheduledFuture!Object periodic = service.scheduleAtFixedRate(new Counter, 10_000, 10_000, TimeUnit.MILLISECONDS);
    assert(!(cast(RunnableScheduledFuture!int) oneShot).isPeriodic());
    assert((cast(RunnableScheduledFuture!Object) periodic).isPeriodic());
    service.shutdownNow();
    awaitTermination(service);
}

@("scheduled awaitTermination waits for the worker to finish after shutdown")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    service.schedule(new Value(1), 10, TimeUnit.MILLISECONDS).get(5, TimeUnit.SECONDS);
    service.shutdown();
    assert(service.awaitTermination(5, TimeUnit.SECONDS));
    assert(service.isTerminated());
}

@("scheduled awaitTermination times out while the worker is running")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    scope (exit)
        service.shutdownNow();
    const started = Deadline.afterMillis(0).monotonicNanoseconds;
    assert(!service.awaitTermination(50, TimeUnit.MILLISECONDS));
    assert(Deadline.afterMillis(0).monotonicNanoseconds - started >= 50_000_000L);
    assert(!service.isShutdown());
}

@("scheduled close shuts the worker down and returns after termination")
unittest
{
    auto service = new OffloadScheduledExecutorService;
    service.close();
    assert(service.isShutdown() && service.isTerminated());
}

@("scheduled awaitTermination throws InterruptedException when the thread is already interrupted")
unittest
{
    import flint.java.lang.interruptedexception : InterruptedException;
    import flint.java.lang.thread : JavaThread = Thread;

    auto service = new OffloadScheduledExecutorService;
    scope (exit)
        service.shutdownNow();
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
}
