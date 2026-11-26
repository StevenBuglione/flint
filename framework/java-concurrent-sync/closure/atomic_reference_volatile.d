module atomic_reference_volatile_probe;

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
    reference.set(first);
    if (reference.get() !is first || !reference.compareAndSet(first, null))
        return 128;
    if (reference.compareAndExchange(null, first) !is null)
        return 129;
    return reference.getAndSet(null).value & 127;
}
