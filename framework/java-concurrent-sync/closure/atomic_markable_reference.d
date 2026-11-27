module atomic_markable_reference_probe;

import flint.java.util.concurrent.atomic.atomicmarkablereference : AtomicMarkableReference;

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
    auto reference = new AtomicMarkableReference!Reading(first, false);
    if (!reference.compareAndSet(first, second, false, true))
        return 128;
    if (!reference.attemptMark(second, false))
        return 129;
    if (!reference.weakCompareAndSet(second, first, false, false))
        return 130;
    reference.set(first, reference.isMarked());
    return reference.getReference().value & 127;
}
