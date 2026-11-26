module atomic_reference_probe;

import flint.java.util.concurrent.atomic.atomicreference : AtomicReference;

@safe:

private final class Reading
{
    const int value;

    this(int value)
    {
        this.value = value;
    }
}

pragma(inline, false) private int publish(AtomicReference!Reading reference, Reading next, bool useRelease)
{
    if (useRelease)
        reference.setRelease(next);
    else
        reference.lazySet(next);

    return reference.getAcquire().value & 127;
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    return publish(new AtomicReference!Reading, new Reading(count), count != 0);
}
