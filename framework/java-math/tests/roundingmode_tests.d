module roundingmode_tests;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.math.roundingmode : RoundingMode, compareTo, name, ordinal, toString, valueOf, values;

@safe:

@("Rounding modes retain Java names, ordinal order and legacy codes") unittest
{
    const expected = [
        RoundingMode.UP, RoundingMode.DOWN, RoundingMode.CEILING, RoundingMode.FLOOR,
        RoundingMode.HALF_UP, RoundingMode.HALF_DOWN, RoundingMode.HALF_EVEN, RoundingMode.UNNECESSARY,
    ];
    const names = [
        "UP", "DOWN", "CEILING", "FLOOR", "HALF_UP", "HALF_DOWN", "HALF_EVEN", "UNNECESSARY"
    ];

    assert(values() == expected);
    foreach (i, mode; expected)
    {
        assert(mode.ordinal() == i);
        assert(mode.name() == names[i]);
        assert(mode.toString() == names[i]);
        assert(valueOf(names[i]) == mode);
        assert(valueOf(cast(int) i) == mode);
        assert(mode.compareTo(RoundingMode.UNNECESSARY) == cast(int) i - 7);
    }
}

@("RoundingMode values returns a fresh array") unittest
{
    auto first = values();
    first[0] = RoundingMode.UNNECESSARY;
    assert(values()[0] == RoundingMode.UP);
}

@("RoundingMode rejects invalid names, integer codes and explicit null") unittest
{
    import std.exception : assertThrown;

    assertThrown!IllegalArgumentException(valueOf(""));
    assertThrown!IllegalArgumentException(valueOf("up"));
    assertThrown!IllegalArgumentException(valueOf("UP "));
    assertThrown!IllegalArgumentException(valueOf(-1));
    assertThrown!IllegalArgumentException(valueOf(8));
    assertThrown!NullPointerException(valueOf(null));
    static assert(!__traits(compiles, RoundingMode.UP.compareTo(null)));
}
