module math_exact_test;

import flint.java.lang : ArithmeticException, IllegalArgumentException;
import flint.java.lang.math : Math;

@safe:

// "Class: message" for the Java exception `call` throws, or null when it returns normally.
private string thrown(scope void delegate() @safe call)
{
    try
        call();
    catch (ArithmeticException error)
        return "ArithmeticException: " ~ error.msg;
    catch (IllegalArgumentException error)
        return "IllegalArgumentException: " ~ error.msg;
    return null;
}

private enum intOverflow = "ArithmeticException: integer overflow";
private enum longOverflow = "ArithmeticException: long overflow";
private enum byZero = "ArithmeticException: / by zero";

// Non-throwing calls fold at compile time; an overflow is a compile error, never a wrapped constant.
static assert(Math.floorMod(-7, 3) == 2 && Math.ceilDiv(7L, 2L) == 4L && Math.addExact(int.max - 1, 1) == int.max);
static assert(Math.floorDiv(int.min, -1) == int.min && Math.clamp(-9L, -3, 5) == -3);
static assert(!__traits(compiles, { enum x = Math.addExact(int.max, 1); }));
static assert(!__traits(compiles, { enum x = Math.floorDiv(1, 0); }));

@("Math addExact and subtractExact overflow throws ArithmeticException")
unittest
{
    assert(Math.addExact(int.max - 1, 1) == int.max && Math.addExact(-5, -6) == -11);
    assert(Math.addExact(long.min + 1, -1L) == long.min);
    assert(thrown({ Math.addExact(int.max, 1); }) == intOverflow);
    assert(thrown({ Math.addExact(int.min, -1); }) == intOverflow);
    assert(thrown({ Math.addExact(long.max, 1L); }) == longOverflow);

    assert(Math.subtractExact(int.min + 1, 1) == int.min && Math.subtractExact(-1L, long.max) == long.min);
    assert(thrown({ Math.subtractExact(0, int.min); }) == intOverflow);
    assert(thrown({ Math.subtractExact(long.min, 1L); }) == longOverflow);
}

@("Math multiplyExact overflow throws ArithmeticException on every overload")
unittest
{
    assert(Math.multiplyExact(46_340, 46_340) == 2_147_395_600 && Math.multiplyExact(-1, int.max) == -int.max);
    assert(thrown({ Math.multiplyExact(46_341, 46_341); }) == intOverflow);
    assert(thrown({ Math.multiplyExact(int.min, -1); }) == intOverflow);
    assert(Math.multiplyExact(3_037_000_499L, 3_037_000_499L) == 9_223_372_030_926_249_001L);
    assert(Math.multiplyExact(long.min, 1) == long.min && Math.multiplyExact(0L, long.min) == 0L);
    assert(thrown({ Math.multiplyExact(3_037_000_500L, 3_037_000_500L); }) == longOverflow);
    assert(thrown({ Math.multiplyExact(long.min, -1L); }) == longOverflow);
    assert(thrown({ Math.multiplyExact(-1L, long.min); }) == longOverflow);
    assert(thrown({ Math.multiplyExact(long.min, -1); }) == longOverflow);
}

@("Math increment, decrement, negate and toIntExact overflow throws ArithmeticException")
unittest
{
    assert(Math.incrementExact(-1) == 0 && Math.decrementExact(0L) == -1L);
    assert(thrown({ Math.incrementExact(int.max); }) == intOverflow);
    assert(thrown({ Math.incrementExact(long.max); }) == longOverflow);
    assert(thrown({ Math.decrementExact(int.min); }) == intOverflow);
    assert(thrown({ Math.decrementExact(long.min); }) == longOverflow);
    assert(Math.negateExact(int.max) == int.min + 1 && Math.negateExact(-7L) == 7L);
    assert(thrown({ Math.negateExact(int.min); }) == intOverflow);
    assert(thrown({ Math.negateExact(long.min); }) == longOverflow);

    assert(Math.toIntExact(-2_147_483_648L) == int.min && Math.toIntExact(2_147_483_647L) == int.max);
    assert(thrown({ Math.toIntExact(2_147_483_648L); }) == intOverflow);
    assert(thrown({ Math.toIntExact(long.min); }) == intOverflow);
}

@("Math absExact names the MIN_VALUE it cannot negate")
unittest
{
    assert(Math.absExact(-int.max) == int.max && Math.absExact(long.min + 1) == long.max);
    enum absOverflow = "ArithmeticException: Overflow to represent absolute value of ";
    assert(thrown({ Math.absExact(int.min); }) == absOverflow ~ "Integer.MIN_VALUE");
    assert(thrown({ Math.absExact(long.min); }) == absOverflow ~ "Long.MIN_VALUE");
}

@("Math floor/ceil division and modulus round toward the right infinity")
unittest
{
    assert(Math.floorDiv(7, 2) == 3 && Math.floorDiv(-7, 2) == -4 && Math.floorDiv(7, -2) == -4);
    assert(Math.floorDiv(-7, -2) == 3 && Math.floorDiv(-8, 2) == -4);
    assert(Math.floorMod(7, 3) == 1 && Math.floorMod(-7, 3) == 2 && Math.floorMod(7, -3) == -2);
    assert(Math.floorMod(-7, -3) == -1 && Math.floorMod(-6, 3) == 0);
    assert(Math.ceilDiv(7, 2) == 4 && Math.ceilDiv(-7, 2) == -3 && Math.ceilDiv(-7, -2) == 4);
    assert(Math.ceilMod(7, 3) == -2 && Math.ceilMod(-7, 3) == -1 && Math.ceilMod(7, -3) == 1);
    assert(Math.ceilMod(-7, -3) == 2);

    // The (long, int) overloads: floorMod and ceilMod return int.
    assert(Math.floorDiv(-9_000_000_000L, 7) == -1_285_714_286L);
    static assert(is(typeof(Math.floorMod(-9_000_000_000L, 7)) == int));
    assert(Math.floorMod(-9_000_000_000L, 7) == 2 && Math.ceilMod(9_000_000_000L, 7) == -2);
    assert(Math.ceilDiv(9_000_000_000L, 7) == 1_285_714_286L);
    assert(Math.floorMod(long.min, -1) == 0 && Math.ceilMod(long.min, 2_147_483_647) == -2);
}

@("Math MIN_VALUE / -1 wraps where Java's division does, and the Exact forms throw")
unittest
{
    assert(Math.floorDiv(int.min, -1) == int.min && Math.ceilDiv(int.min, -1) == int.min);
    assert(Math.floorDiv(long.min, -1L) == long.min && Math.ceilDiv(long.min, -1) == long.min);
    assert(Math.floorMod(int.min, -1) == 0 && Math.ceilMod(int.min, -1) == 0);
    assert(Math.floorMod(long.min, -1L) == 0 && Math.ceilMod(long.min, -1L) == 0);

    assert(Math.divideExact(-7, 2) == -3 && Math.divideExact(long.min, 1L) == long.min);
    assert(Math.floorDivExact(-7, 2) == -4 && Math.ceilDivExact(-7L, -2L) == 4L);
    assert(Math.floorDivExact(int.min, 1) == int.min && Math.ceilDivExact(long.min, 2L) == long.min / 2);
    assert(thrown({ Math.divideExact(int.min, -1); }) == intOverflow);
    assert(thrown({ Math.divideExact(long.min, -1L); }) == longOverflow);
    assert(thrown({ Math.floorDivExact(int.min, -1); }) == intOverflow);
    assert(thrown({ Math.floorDivExact(long.min, -1L); }) == longOverflow);
    assert(thrown({ Math.ceilDivExact(int.min, -1); }) == intOverflow);
    assert(thrown({ Math.ceilDivExact(long.min, -1L); }) == longOverflow);
}

@("Math division by zero throws ArithmeticException(\"/ by zero\") instead of trapping")
unittest
{
    assert(thrown({ Math.floorDiv(1, 0); }) == byZero);
    assert(thrown({ Math.floorDiv(1L, 0); }) == byZero);
    assert(thrown({ Math.floorMod(int.min, 0); }) == byZero);
    assert(thrown({ Math.floorMod(1L, 0L); }) == byZero);
    assert(thrown({ Math.ceilDiv(0, 0); }) == byZero);
    assert(thrown({ Math.ceilMod(1L, 0); }) == byZero);
    assert(thrown({ Math.divideExact(1, 0); }) == byZero);
    assert(thrown({ Math.floorDivExact(1L, 0L); }) == byZero);
    assert(thrown({ Math.ceilDivExact(1, 0); }) == byZero);
    // multiplyExact divides only to check a wide product, and never by zero.
    assert(Math.multiplyExact(long.max, 0L) == 0L);
}

@("Math integral clamp, and the IllegalArgumentException text for an empty range")
unittest
{
    assert(Math.clamp(5_000_000_000L, -3, 7) == 7 && Math.clamp(long.min, -3, 7) == -3);
    assert(Math.clamp(4L, 4, 4) == 4 && Math.clamp(-1L, int.min, int.max) == -1);
    assert(Math.clamp(long.max, long.min, long.max) == long.max && Math.clamp(9L, 0L, 3L) == 3L);
    enum empty = "IllegalArgumentException: ";
    assert(thrown({ Math.clamp(0L, 1, 0); }) == empty ~ "1 > 0");
    assert(thrown({ Math.clamp(0L, int.max, int.min); }) == empty ~ "2147483647 > -2147483648");
    assert(thrown({ Math.clamp(0L, long.max, long.min); }) == empty ~ "9223372036854775807 > -9223372036854775808");
    assert(thrown({ Math.clamp(0L, -1L, -10L); }) == empty ~ "-1 > -10");
}
