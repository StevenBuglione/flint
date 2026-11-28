module futuretask_probe;

import flint.java.util.concurrent.futuretask : FutureTask;
import std.traits : InterfacesTuple, Parameters;

@safe:

private template pickRunnable(Bases...)
{
    static if (Bases.length == 0)
        alias pickRunnable = void;
    else static if (__traits(identifier, Bases[0]) == "Runnable")
        alias pickRunnable = Bases[0];
    else
        alias pickRunnable = pickRunnable!(Bases[1 .. $]);
}

private alias Runnable = pickRunnable!(InterfacesTuple!(FutureTask!int));
private alias TimeUnit = Parameters!(__traits(getOverloads, FutureTask!int, "get")[1])[1];

private final class Work : Runnable
{
    override void run()
    {
    }
}

int main(string[] args)
{
    FutureTask!int task = new FutureTask!int(new Work, cast(int) args.length);
    if (args.length > 2)
    {
        if (!task.cancel(false))
            return 1;
        try
            return task.get() == 0 ? 0 : 1;
        catch (Exception)
            return 0;
    }

    task.run();
    if (!task.isDone || task.isCancelled)
        return 1;
    return task.get(1, TimeUnit.init) == cast(int) args.length ? 0 : 1;
}
