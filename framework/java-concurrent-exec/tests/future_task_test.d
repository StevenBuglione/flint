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
    assert(task.cancel(false));
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
