/// Java SE 21 rounding directions and legacy BigDecimal mode codes (rules R7 and R20).
module flint.java.math.roundingmode;

import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

/// Selects the direction used when an exact value cannot be represented.
enum RoundingMode
{
    UP,
    DOWN,
    CEILING,
    FLOOR,
    HALF_UP,
    HALF_DOWN,
    HALF_EVEN,
    UNNECESSARY,
}

private static immutable string[RoundingMode.max + 1] names = [
    "UP", "DOWN", "CEILING", "FLOOR", "HALF_UP", "HALF_DOWN", "HALF_EVEN", "UNNECESSARY",
];

/// Return the declared name of the rounding mode.
string name(RoundingMode mode) pure nothrow @nogc
{
    return names[mode];
}

/// Return the position of the mode in declaration order.
int ordinal(RoundingMode mode) pure nothrow @nogc
{
    return cast(int) mode;
}

/// Render the declared name.
string toString(RoundingMode mode) pure nothrow @nogc
{
    return name(mode);
}

/// Compare rounding modes by declaration order.
int compareTo(RoundingMode left, RoundingMode right) pure nothrow @nogc
{
    return ordinal(left) - ordinal(right);
}

/// Return a fresh array of the modes in declaration order.
RoundingMode[] values() pure nothrow
{
    auto modes = new RoundingMode[names.length];
    foreach (i, ref mode; modes)
        mode = cast(RoundingMode) i;
    return modes;
}

/// Find a mode by its exact Java name.
RoundingMode valueOf(scope const(char)[] spelling)
{
    foreach (i, candidate; names)
        if (candidate == spelling)
            return cast(RoundingMode) i;
    throw new IllegalArgumentException("Unknown rounding mode");
}

RoundingMode valueOf(typeof(null))
{
    throw new NullPointerException();
}

/// Convert a legacy BigDecimal rounding code.
RoundingMode valueOf(int mode)
{
    if (cast(uint) mode >= names.length)
        throw new IllegalArgumentException("Invalid rounding mode");
    return cast(RoundingMode) mode;
}
