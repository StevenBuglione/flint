module atomic_reference_weak_probe;

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

int main(string[] args)
{
    auto first = new Reading(cast(int) args.length - 1);
    auto reference = new AtomicReference!Reading;
    if (!reference.weakCompareAndSetRelease(null, first))
        return 128;
    if (!reference.weakCompareAndSetAcquire(first, first))
        return 129;
    if (!reference.weakCompareAndSetPlain(first, null))
        return 130;
    if (!reference.weakCompareAndSetVolatile(null, first))
        return 131;
    if (!reference.weakCompareAndSet(first, first))
        return 132;
    return reference.getAcquire().value & 127;
}
