/** Original Flint tests for the Java SE 21 Callable contract. */
module callable_test;

import flint.java.util.concurrent.callable : Callable;

@safe:

private final class TextTask : Callable!string
{
    private string value;
    private Exception failure;

    this(string value, Exception failure = null)
    {
        this.value = value;
        this.failure = failure;
    }

    override string call()
    {
        if (failure !is null)
            throw failure;
        return value;
    }
}

@("Callable dispatches a result or propagates the task exception")
unittest
{
    Callable!string task = new TextTask("completed");
    assert(task.call() == "completed");

    task = new TextTask(null);
    assert(task.call() is null);

    auto failure = new Exception("task failed");
    task = new TextTask(null, failure);
    try
    {
        task.call();
        assert(false, "call returned instead of throwing");
    }
    catch (Exception caught)
    {
        assert(caught is failure);
    }
}
