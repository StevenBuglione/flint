module scheduled_future_test;

import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.future : Future;
import flint.java.util.concurrent.scheduledfuture : RunnableScheduledFuture, ScheduledFuture;

@safe:

private final class Job : RunnableScheduledFuture!int
{
    mixin Future!int.Defaults;

    private long remaining;
    private bool periodic;

    this(long remaining, bool periodic = false) pure nothrow @nogc
    {
        this.remaining = remaining;
        this.periodic = periodic;
    }

    override void run() pure nothrow @nogc
    {
    }

    override bool isPeriodic() pure nothrow @nogc
    {
        return periodic;
    }

    override bool cancel(bool mayInterruptIfRunning) pure nothrow @nogc
    {
        return false;
    }

    override bool isCancelled() pure nothrow @nogc
    {
        return false;
    }

    override bool isDone() pure nothrow @nogc
    {
        return remaining <= 0;
    }

    override int get() pure nothrow @nogc
    {
        return 7;
    }

    override int get(long timeout, TimeUnit unit) pure nothrow @nogc
    {
        return get() + cast(int) timeout;
    }

    override long getDelay(TimeUnit unit) pure nothrow @nogc
    {
        return unit == TimeUnit.NANOSECONDS ? remaining : remaining / 1_000;
    }

    override int compareTo(Delayed other)
    {
        const otherRemaining = other.getDelay(TimeUnit.NANOSECONDS);
        return (remaining > otherRemaining) - (remaining < otherRemaining);
    }
}

@("a scheduled future is a Delayed Future, and a runnable one is also a Runnable")
unittest
{
    Job job = new Job(1_000);
    ScheduledFuture!int scheduled = job;
    const Future!int future = job;
    const Delayed delayed = job;

    assert(future is job);
    assert(delayed is job);
    assert(scheduled.get() == 7);
}

@("getDelay converts the remaining time in the requested unit")
unittest
{
    Job job = new Job(1_000_000);

    assert(job.getDelay(TimeUnit.NANOSECONDS) == 1_000_000);
    assert(job.getDelay(TimeUnit.MICROSECONDS) == 1_000);
    assert(!job.isDone);
}

@("compareTo orders tasks by remaining delay")
unittest
{
    Job soon = new Job(1_000);
    Job later = new Job(2_000);

    assert(soon.compareTo(later) < 0);
    assert(later.compareTo(soon) > 0);
    assert(soon.compareTo(soon) == 0);
}

@("isPeriodic reports the task's scheduling mode")
unittest
{
    assert(!(new Job(1)).isPeriodic);
    assert((new Job(1, true)).isPeriodic);
}
