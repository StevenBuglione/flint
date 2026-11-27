module future_probe;

import flint.java.util.concurrent.future : Future;
import std.traits : Parameters;

@safe:

private alias TimeUnit = Parameters!(__traits(getOverloads, Future!int, "get")[1])[1];

private final class Station : Future!int
{
    private int mode;

    this(int mode) pure nothrow @nogc
    {
        this.mode = mode;
    }

    override bool cancel(bool mayInterruptIfRunning) pure nothrow @nogc
    {
        return !mayInterruptIfRunning && !isDone();
    }

    override bool isCancelled() pure nothrow @nogc
    {
        return mode == 3;
    }

    override bool isDone() pure nothrow @nogc
    {
        return mode != 0;
    }

    override int get()
    {
        return mode * 7;
    }

    override int get(long timeout, TimeUnit unit)
    {
        return get() + cast(int) timeout + cast(int) unit;
    }
}

int main(string[] args)
{
    const mode = args.length % 4;
    Future!int stage = new Station(mode);
    try
    {
        if (stage.state() == Future!int.State.RUNNING)
            return stage.resultNow;
        return stage.resultNow + stage.get(1, TimeUnit.init);
    }
    catch (Exception failure)
    {
        try
            return stage.exceptionNow() is null;
        catch (Exception inner)
            return 1 + mode;
    }
}
