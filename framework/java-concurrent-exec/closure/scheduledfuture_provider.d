module scheduledfuture_provider;

import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.future : Future;

@safe:

// Provider-equivalent control: the inherited Delayed, Future and Runnable APIs without the new leaf's interfaces.
private final class Job : Delayed, Future!int, Runnable
{
    mixin Future!int.Defaults;

    private long remaining;

    this(long remaining)
    {
        this.remaining = remaining;
    }

    void run()
    {
    }

    bool isPeriodic()
    {
        return false;
    }

    bool cancel(bool)
    {
        return false;
    }

    bool isCancelled()
    {
        return false;
    }

    bool isDone()
    {
        return remaining <= 0;
    }

    int get()
    {
        return 7;
    }

    int get(long timeout, TimeUnit unit)
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

pragma(inline, false) private int witness(Job job, Delayed pivot)
{
    if (job.isPeriodic || job.isCancelled)
        return 1;
    if (job.compareTo(pivot) < 0)
        return 0;
    return job.get(0, TimeUnit.MILLISECONDS);
}

int main(string[] args)
{
    Job job = new Job(1_000L * args.length - 2_000);
    return witness(job, new Job(0)) == 0 ? 0 : 1;
}
