module future_test;

import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.future : Future;

@safe:

private final class FakeFuture : Future!int
{
    mixin Future!int.Defaults;

    enum Kind
    {
        running,
        success,
        failed,
        cancelled,
    }

    private Kind kind;
    private int value;
    private Throwable error;

    this(Kind kind, int value = 0, Throwable error = null) pure nothrow @nogc
    {
        this.kind = kind;
        this.value = value;
        this.error = error;
    }

    override bool cancel(bool mayInterruptIfRunning) pure nothrow @nogc
    {
        return false;
    }

    override bool isCancelled() pure nothrow @nogc
    {
        return kind == Kind.cancelled;
    }

    override bool isDone() pure nothrow @nogc
    {
        return kind != Kind.running;
    }

    override int get()
    {
        final switch (kind)
        {
        case Kind.running:
            throw new IllegalStateException("still running");
        case Kind.success:
            return value;
        case Kind.failed:
            throw new ExecutionException(error);
        case Kind.cancelled:
            throw new CancellationException("cancelled");
        }
    }

    override int get(long timeout, TimeUnit unit)
    {
        return get();
    }
}

private IllegalStateException capturedISE(scope void delegate() @safe operation)
{
    try
        operation();
    catch (IllegalStateException failure)
        return failure;
    assert(false, "expected IllegalStateException");
}

@("a running task reports RUNNING and the two now-or-never readers refuse it")
unittest
{
    FakeFuture running = new FakeFuture(FakeFuture.Kind.running);

    assert(running.state() == Future!int.State.RUNNING);
    assert(capturedISE(() { running.resultNow(); }).getMessage() == "Task has not completed");
    assert(capturedISE(() { running.exceptionNow(); }).getMessage() == "Task has not completed");
}

@("a successful task returns its value and refuses to report an exception")
unittest
{
    FakeFuture success = new FakeFuture(FakeFuture.Kind.success, 42);

    assert(success.state() == Future!int.State.SUCCESS);
    assert(success.resultNow() == 42);
    assert(success.get(1, TimeUnit.SECONDS) == 42);
    assert(capturedISE(() { success.exceptionNow(); }).getMessage() == "Task completed with a result");
}

@("a failed task reports FAILED and exposes the ExecutionException's cause")
unittest
{
    auto boom = new RuntimeException("boom");
    FakeFuture failed = new FakeFuture(FakeFuture.Kind.failed, 0, boom);

    assert(failed.state() == Future!int.State.FAILED);
    assert(failed.exceptionNow() is boom);

    auto refusal = capturedISE(() { failed.resultNow(); });
    assert(refusal.getMessage() == "Task completed with exception");
    auto wrapper = cast(ExecutionException) refusal.getCause();
    assert(wrapper !is null && wrapper.getCause() is boom);
}

@("a cancelled task reports CANCELLED before it is asked for a value")
unittest
{
    FakeFuture cancelled = new FakeFuture(FakeFuture.Kind.cancelled);

    assert(cancelled.state() == Future!int.State.CANCELLED);
    assert(capturedISE(() { cancelled.resultNow(); }).getMessage() == "Task was cancelled");
    assert(capturedISE(() { cancelled.exceptionNow(); }).getMessage() == "Task was cancelled");
}

@("the State names match Java's Future.State")
unittest
{
    static assert(Future!int.State.RUNNING < Future!int.State.SUCCESS);
    static assert(Future!int.State.SUCCESS < Future!int.State.FAILED);
    static assert(Future!int.State.FAILED < Future!int.State.CANCELLED);
}
