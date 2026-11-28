module future_task_test;

import core.thread.osthread : Thread; // ADR-026 requires the declaring module on DMD for Windows.
import flint.java.lang : NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.future : FutureState;
import flint.java.util.concurrent.futuretask : FutureTask;
import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

private final class Value : Callable!int
{
    private int value;

    this(int value) pure nothrow @nogc
    {
        this.value = value;
    }

    override int call()
    {
        return value;
    }
}

private final class Failing : Callable!int
{
    private Throwable error;

    this(Throwable error) pure nothrow @nogc
    {
        this.error = error;
    }

    override int call()
    {
        throw error;
    }
}

private final class Counter : Runnable
{
    int runs;

    override void run()
    {
        runs++;
    }
}

// Java's `FutureTask` keeps `NEW` while its callable runs, so a cancel from inside the task succeeds and the result
// is discarded. This fixture exercises that state without a second OS thread.
private final class SelfCancelling : Callable!int
{
    FutureTask!int task;
    bool cancelled;

    override int call()
    {
        cancelled = task.cancel(false);
        return 7;
    }
}

@("FutureTask runs its Callable once and exposes the result")
unittest
{
    auto task = new FutureTask!int(new Value(42));
    assert(!task.isDone);
    assert(task.state == FutureState.RUNNING);

    task.run();
    assert(task.isDone && !task.isCancelled);
    assert(task.state == FutureState.SUCCESS);
    assert(task.get == 42);
    assert(task.get(0, TimeUnit.NANOSECONDS) == 42);
    assert(task.resultNow == 42);

    task.run();
    assert(task.get == 42);
}

@("FutureTask wraps a Runnable and its fixed result")
unittest
{
    auto counter = new Counter;
    auto task = new FutureTask!int(counter, 7);
    task.run();
    assert(counter.runs == 1);
    assert(task.get == 7);
}

@("FutureTask reports a failed Callable through ExecutionException and exceptionNow")
unittest
{
    auto error = new Exception("boom");
    auto task = new FutureTask!int(new Failing(error));
    task.run();

    assert(task.isDone && !task.isCancelled);
    assert(task.state == FutureState.FAILED);
    assert(task.exceptionNow is error);
    try
    {
        task.get();
        assert(false, "get must throw");
    }
    catch (ExecutionException failure)
    {
        assert(failure.getCause is error);
    }
}

@("FutureTask cancel before run makes get throw CancellationException")
unittest
{
    auto task = new FutureTask!int(new Value(1));
    assert(task.cancel(false));
    assert(task.isCancelled && task.isDone);
    assert(task.state == FutureState.CANCELLED);
    assert(!task.cancel(false));
    assert(!task.cancel(true));
    try
    {
        task.get();
        assert(false, "get must throw");
    }
    catch (CancellationException)
    {
    }
    try
    {
        task.resultNow();
        assert(false, "resultNow must throw");
    }
    catch (Exception failure)
    {
        assert(cast(CancellationException) failure is null);
    }
}

@("FutureTask cancel(false) from a running task succeeds and discards the result")
unittest
{
    auto callable = new SelfCancelling;
    auto task = new FutureTask!int(callable);
    callable.task = task;

    task.run();

    assert(callable.cancelled, "Java's FutureTask cancels while its callable is running");
    assert(task.isCancelled && task.isDone);
    assert(task.state == FutureState.CANCELLED);
    assert(!task.cancel(false));
    try
    {
        task.get();
        assert(false, "get must throw");
    }
    catch (CancellationException)
    {
    }
}

@("FutureTask cancel after normal completion returns false")
unittest
{
    auto task = new FutureTask!int(new Value(3));
    task.run();

    assert(!task.cancel(false));
    assert(!task.cancel(true));
    assert(task.get == 3);
}

@("FutureTask wraps a CancellationException thrown by its Callable")
unittest
{
    auto error = new CancellationException("from the task");
    auto task = new FutureTask!int(new Failing(error));
    task.run();

    assert(task.isDone && !task.isCancelled);
    assert(task.state == FutureState.FAILED);
    assert(task.exceptionNow is error);
    try
    {
        task.get();
        assert(false, "get must throw ExecutionException");
    }
    catch (ExecutionException failure)
    {
        assert(failure.getCause is error);
    }
}

@("FutureTask get with a timeout fails when the task has not run")
unittest
{
    auto task = new FutureTask!int(new Value(1));
    foreach (timeout; [-1L, 0L, 1L])
    {
        try
        {
            task.get(timeout, TimeUnit.MILLISECONDS);
            assert(false, "get must time out");
        }
        catch (TimeoutException)
        {
        }
    }
    assert(!task.isDone);
}

@("FutureTask constructor rejects a null task")
unittest
{
    try
    {
        new FutureTask!int(cast(Callable!int) null);
        assert(false, "constructor must throw");
    }
    catch (NullPointerException)
    {
    }
}

@("FutureTask get waits for another thread to publish the result")
@system unittest
{
    auto task = new FutureTask!int(new Value(1234));
    auto worker = new Thread(() { task.run(); });
    worker.start();
    scope (exit)
        worker.join();

    assert(task.get() == 1234);
}

@("FutureTask get throws InterruptedException when the calling thread is already interrupted")
unittest
{
    import flint.java.lang.interruptedexception : InterruptedException;
    import flint.java.lang.thread : JavaThread = Thread;

    auto task = new FutureTask!int(new Value(1));
    JavaThread.currentThread().interrupt();
    try
    {
        task.get();
        assert(false, "get must throw InterruptedException");
    }
    catch (InterruptedException)
    {
    }
    // Java clears the flag when it throws.
    assert(!JavaThread.currentThread().isInterrupted());
    assert(!task.isDone);
}

@("FutureTask get wakes and throws when another thread interrupts the waiter")
@system unittest
{
    import core.atomic : atomicLoad, atomicStore;
    import flint.java.lang.interruptedexception : InterruptedException;
    import flint.java.lang.thread : JavaThread = Thread;

    auto task = new FutureTask!int(new Value(1));
    __gshared JavaThread waiter;
    __gshared bool started;
    __gshared bool interrupted;
    __gshared bool flagCleared;
    auto worker = new Thread({
        auto self = JavaThread.currentThread();
        waiter = self;
        atomicStore(started, true);
        try
            task.get(10, TimeUnit.SECONDS);
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
    assert(flagCleared, "Java clears the flag when get throws");
    assert(!task.isDone);
}
