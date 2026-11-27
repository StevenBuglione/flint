module atomic_stamped_reference_probe;

import flint.java.util.concurrent.atomic.atomicstampedreference : AtomicStampedReference;

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
    auto second = new Reading(1);
    auto reference = new AtomicStampedReference!Reading(first, 0);
    if (!reference.compareAndSet(first, second, 0, 1))
        return 128;
    if (!reference.attemptStamp(second, 2))
        return 129;
    if (!reference.weakCompareAndSet(second, first, 2, 3))
        return 130;
    reference.set(first, reference.getStamp());
    return reference.getReference().value & 127;
}
