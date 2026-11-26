module executor_probe;

import flint.java.util.concurrent.executor : Executor;
import std.traits : Parameters;

@safe:

private alias Runnable = Parameters!(__traits(getOverloads, Executor, "execute")[0])[0];

private final class InlineExecutor : Executor
{
    override void execute(Runnable command)
    {
        command.run();
    }
}

private final class Invocation : Runnable
{
    bool ran;

    override void run()
    {
        ran = true;
    }
}

int main(string[] args)
{
    Executor executor = new InlineExecutor;
    if (args.length > 1)
    {
        auto task = new Invocation;
        executor.execute(task);
        return task.ran ? 0 : 1;
    }
    bool ran;
    executor.execute(() { ran = true; });
    return ran ? 0 : 1;
}
