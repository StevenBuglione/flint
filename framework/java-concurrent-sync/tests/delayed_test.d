module delayed_test;

import flint.java.lang : Comparable;
import flint.java.util.concurrent : TimeUnit, convert, toNanos;
import flint.java.util.concurrent.delayed : Delayed;

@safe:

private final class DeadlineValue : Delayed
{
    private long remaining;

    this(long remaining)
    {
        this.remaining = remaining;
    }

    override long getDelay(TimeUnit unit)
    {
        return unit.convert(remaining, TimeUnit.NANOSECONDS);
    }

    override int compareTo(Delayed other)
    {
        const otherRemaining = other.getDelay(TimeUnit.NANOSECONDS);
        return (remaining > otherRemaining) - (remaining < otherRemaining);
    }
}

@("Delayed is ordered through the canonical Comparable specialization")
unittest
{
    static assert(is(Delayed : Comparable!Delayed));
    static assert(!__traits(compiles, (Delayed value) => value.getDelay(null)));

    Delayed expired = new DeadlineValue(-2_000);
    Delayed future = new DeadlineValue(3_000);
    Comparable!Delayed ordered = expired;
    assert(ordered.compareTo(future) < 0);
    assert(future.compareTo(expired) > 0);
    assert(expired.getDelay(TimeUnit.MICROSECONDS) == -2);
    assert(future.getDelay(TimeUnit.NANOSECONDS) == TimeUnit.MICROSECONDS.toNanos(3));
}
