module app;

import flint.java.time.temporal.chronofield : ChronoField, isDateBased, isTimeBased, range;

@safe:

int main(string[] args)
{
    const field = cast(ChronoField)(args.length % (cast(size_t) ChronoField.max + 1));
    const bounds = field.range();
    ulong checksum = cast(ulong) bounds.getMinimum() + 3UL * cast(ulong) bounds.getLargestMinimum();
    checksum += 5UL * cast(ulong) bounds.getSmallestMaximum() + 7UL * cast(ulong) bounds.getMaximum();
    checksum += (field.isDateBased() ? 1 : 0) + (field.isTimeBased() ? 2 : 0);
    return cast(int)(checksum ^ (checksum >> 32));
}
