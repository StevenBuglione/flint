module executor_contract_test;

import core.memory : GC;
import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.executor : Executor;
import std.exception : assertThrown;

@safe:

private final class Task : Runnable
{
    int calls;

    override void run()
    {
        ++calls;
    }
}

private final class HoldingExecutor : Executor
{
    Runnable pending;
    size_t nullArguments;

    override void execute(Runnable command)
    {
        if (command is null)
        {
            ++nullArguments;
            throw new NullPointerException;
        }
        pending = command;
    }
}

@("the Executor contract accepts the canonical Runnable by identity")
unittest
{
    auto recording = new HoldingExecutor;
    Executor executor = recording;
    auto task = new Task;
    executor.execute(task);
    assert(recording.pending is task);
    assert(task.calls == 0);
    recording.pending.run();
    assert(task.calls == 1);
}

@("a queued D delegate retains its closure and propagates its failure")
unittest
{
    auto recording = new HoldingExecutor;
    Executor executor = recording;
    auto task = new Task;
    submitOwnedDelegate(executor, task);
    assert(task.calls == 0);
    GC.collect();
    recording.pending.run();
    assert(task.calls == 1);

    auto original = new IllegalStateException("same failure");
    executor.execute(() { throw original; });
    try
    {
        recording.pending.run();
        assert(false, "expected the original failure to propagate");
    }
    catch (IllegalStateException failure)
    {
        assert(failure is original);
    }
}

@("null selects the Runnable overload and null delegates fail before enqueue")
unittest
{
    auto recording = new HoldingExecutor;
    Executor executor = recording;
    assertThrown!NullPointerException(executor.execute(cast(Runnable) null));
    assertThrown!NullPointerException(executor.execute(null));
    assert(recording.nullArguments == 2);

    void delegate() @safe absent;
    assertThrown!NullPointerException(executor.execute(absent));
    assert(recording.pending is null && recording.nullArguments == 2);
}

private void submitOwnedDelegate(Executor executor, Task task)
{
    executor.execute(() { task.run(); });
}
