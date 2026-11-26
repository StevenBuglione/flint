module app;

import flint.java.time.temporal.valuerange : ValueRange;

@safe:

int main(string[] args)
{
    const lower = args.length > 1 ? cast(long) args[1].length : 1;
    const upper = args.length > 2 ? cast(long) args[2].length : 31;
    ValueRange range;
    if (args.length > 4)
        range = ValueRange.of(lower, cast(long) args[3].length, cast(long) args[4].length, upper);
    else if (args.length > 3)
        range = ValueRange.of(lower, cast(long) args[3].length, upper);
    else
        range = ValueRange.of(lower, upper);
    return range.isValidIntValue(cast(long) args.length) ? 0 : 1;
}
