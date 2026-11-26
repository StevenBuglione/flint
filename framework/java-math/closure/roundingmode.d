module app;

import flint.java.math.roundingmode : RoundingMode, compareTo, name, ordinal, toString, valueOf, values;

@safe:

int main(string[] args)
{
    const code = cast(int) args.length - 1;
    const mode = args.length > 1 ? valueOf(args[1]) : valueOf(code);
    if (args.length > 8)
        return valueOf(null).ordinal();
    if (mode.toString() != mode.name() || values()[mode.ordinal()] != mode)
        return 2;
    return mode.compareTo(RoundingMode.UP);
}
