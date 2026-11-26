module delayed_probe;

import flint.java.util.concurrent.delayed : Delayed;
import std.traits : Parameters;

@safe:

private alias TimeUnit = Parameters!(Delayed.getDelay)[0];

private final class DeadlineValue : Delayed
{
    private long remaining;

    this(long remaining)
    {
        this.remaining = remaining;
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

pragma(inline, false) private int witness(Delayed value, Delayed pivot)
{
    if (value.compareTo(pivot) < 0)
        return 0;
    return cast(int) value.getDelay(TimeUnit.MICROSECONDS) & 127;
}

int main(string[] args)
{
    return witness(new DeadlineValue(1_000L * args.length - 2_000), new DeadlineValue(0));
}
