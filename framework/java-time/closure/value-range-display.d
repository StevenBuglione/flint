module app;

import flint.java.time.temporal.valuerange : ValueRange;

@safe:

int main(string[] args)
{
    const lower = -cast(long) args.length;
    const upper = cast(long) args.length;
    const inner = args.length > 1 ? 0 : lower;
    const display = ValueRange.of(lower, inner, -inner, upper).toString();
    return display[0] + display[$ - 1];
}
