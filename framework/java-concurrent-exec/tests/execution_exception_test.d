module execution_exception_test;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.thread : Thread;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import std.exception : assertThrown;

private final class DerivedExecutionException : ExecutionException
{
    this()
    {
        super();
    }

    this(string detail)
    {
        super(detail);
    }
}

private final class NamedCause : RuntimeException
{
    override string toString() const
    {
        return "custom cause";
    }
}

@("constructor accessibility and checked exception hierarchy")
unittest
{
    static assert(is(ExecutionException : Exception));
    static assert(!is(ExecutionException : RuntimeException));
    static assert(!__traits(compiles, new ExecutionException()));
    static assert(!__traits(compiles, new ExecutionException("private detail")));

    auto empty = new DerivedExecutionException;
    assert(empty.getMessage() is null && empty.getCause() is null);
    auto detail = new DerivedExecutionException("detail");
    assert(detail.getMessage() == "detail" && detail.getCause() is null);
}

@("empty execution exception details are absent and display the dynamic class name")
unittest
{
    string text = "deliberate detail";
    string emptySlice = text[0 .. 0];
    assert(emptySlice !is null);
    auto original = new IllegalArgumentException("original");
    foreach (message; [cast(string) null, "", emptySlice])
    {
        auto derived = new DerivedExecutionException(message);
        assert(derived.getMessage() is null);
        assert(derived.toString() == typeid(derived).name);
        assert(derived.initCause(original) is derived);

        auto explicitCause = new ExecutionException(message, original);
        assert(explicitCause.getMessage() is null);
        assert(explicitCause.toString() == typeid(explicitCause).name);
        assert(explicitCause.getCause() is original);
    }
    auto detailed = new ExecutionException(text, original);
    assert(detailed.getMessage() == text);
    assert(detailed.toString() == typeid(detailed).name ~ ": " ~ text);
}

@("explicit causes preserve identity and are already initialized")
unittest
{
    auto original = new IllegalArgumentException("original");
    auto detail = new ExecutionException("details", original);
    assert(detail.getCause() is original && detail.getMessage() == "details");
    assertThrown!IllegalStateException(detail.initCause(null));

    auto diagnosed = new ExecutionException(original);
    assert(diagnosed.getCause() is original && diagnosed.getMessage() == original.toString());
    auto customCause = new NamedCause;
    auto custom = new ExecutionException(customCause);
    assert(custom.getCause() is customCause && custom.getMessage() == "custom cause");

    auto nullable = new ExecutionException("detail", null);
    assert(nullable.getCause() is null && nullable.getMessage() == "detail");
    assertThrown!IllegalStateException(nullable.initCause(original));
    auto nullCause = new ExecutionException(cast(Throwable) null);
    assert(nullCause.getCause() is null && nullCause.getMessage() is null);
    assertThrown!IllegalStateException(nullCause.initCause(original));
}

@("a protected constructor allows one cause and rejects self-causation without consuming it")
unittest
{
    auto failure = new DerivedExecutionException;
    auto cause = new IllegalArgumentException("original");
    try
    {
        failure.initCause(failure);
        assert(false, "expected self-causation to fail");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.getCause() is failure);
        assert(error.getMessage() == "Self-causation not permitted");
    }
    assert(failure.getCause() is null);
    assert(failure.initCause(cause) is failure && failure.getCause() is cause);
    try
    {
        failure.initCause(null);
        assert(false, "expected second initialization to fail");
    }
    catch (IllegalStateException error)
    {
        assert(error.getCause() is failure);
        assert(error.getMessage() == "Can't overwrite cause with a null");
    }
    auto explicitNull = new DerivedExecutionException("detail");
    assert(explicitNull.initCause(null) is explicitNull);
    assertThrown!IllegalStateException(explicitNull.initCause(cause));
}

@("concurrent cause initialization commits only one value")
@system unittest
{
    foreach (round; 0 .. 512)
    {
        auto pending = new DerivedExecutionException;
        Throwable[2] causes = [
            new IllegalArgumentException("first"), new IllegalArgumentException("second")
        ];
        shared uint ready;
        shared bool start;
        shared uint successes;
        Thread[2] workers;
        foreach (index, ref worker; workers)
        {
            auto cause = causes[index];
            worker = new Thread({
                atomicOp!"+="(ready, 1u);
                while (!atomicLoad(start))
                    Thread.yield();
                try
                {
                    pending.initCause(cause);
                    atomicOp!"+="(successes, 1u);
                }
                catch (IllegalStateException failure)
                {
                    assert(failure.getCause() is pending);
                }
            }).start();
        }
        while (atomicLoad(ready) != workers.length)
            Thread.yield();
        atomicStore(start, true);
        foreach (worker; workers)
            worker.join();
        assert(atomicLoad(successes) == 1);
        assert(pending.getCause() is causes[0] || pending.getCause() is causes[1]);
    }
}
