module scheduledfuture_probe;

import flint.java.util.concurrent.scheduledfuture : RunnableScheduledFuture;
import std.traits : InterfacesTuple, Parameters;

@safe:

private template pickDelayed(Bases...)
{
    static if (Bases.length == 0)
        alias pickDelayed = void;
    else static if (__traits(identifier, Bases[0]) == "Delayed")
        alias pickDelayed = Bases[0];
    else
        alias pickDelayed = pickDelayed!(Bases[1 .. $]);
}

private alias Delayed = pickDelayed!(InterfacesTuple!(RunnableScheduledFuture!int));
private alias TimeUnit = Parameters!(__traits(getOverloads, RunnableScheduledFuture!int, "get")[1])[1];

private final class Job : RunnableScheduledFuture!int
{
    mixin Scheduled.Defaults;

    private long remaining;

    this(long remaining)
    {
        this.remaining = remaining;
    }

    override void run()
    {
    }

    override bool isPeriodic()
    {
        return false;
    }

    override bool cancel(bool mayInterruptIfRunning)
    {
        return false;
    }

    override bool isCancelled()
    {
        return false;
    }

    override bool isDone()
    {
        return remaining <= 0;
    }

    override int get()
    {
        return 7;
    }

    override int get(long timeout, TimeUnit unit)
    {
        return get() + cast(int) timeout + cast(int) unit;
    }

    override long getDelay(TimeUnit unit)
    {
        return unit == TimeUnit.NANOSECONDS ? remaining : remaining / 1_000;
    }

    override int compareTo(Delayed other)
    {
        const otherRemaining = other.getDelay(TimeUnit.NANOSECONDS);
        return (remaining > otherRemaining) - (remaining < otherRemaining);
    }
}

pragma(inline, false) private int witness(Scheduled job, Delayed pivot)
{
    if (job.isPeriodic || job.isCancelled)
        return 1;
    if (job.compareTo(pivot) < 0)
        return 0;
    return job.get(0, TimeUnit.MILLISECONDS);
}

private alias Scheduled = RunnableScheduledFuture!int;

int main(string[] args)
{
    Job job = new Job(1_000L * args.length - 2_000);
    return witness(job, new Job(0)) == 0 ? 0 : 1;
}
