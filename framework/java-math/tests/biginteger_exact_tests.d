module biginteger_exact_tests;

import flint.java.lang : ArithmeticException;
import flint.java.math.biginteger : BigInteger;

@safe:

@("BigInteger integral factories and Java signed conversion boundaries")
unittest
{
    assert(BigInteger.valueOf(long.min).longValueExact() == long.min);
    assert(BigInteger.valueOf(long.max).longValueExact() == long.max);
    assert(BigInteger.valueOf(int.min).intValueExact() == int.min);
    assert(BigInteger.valueOf(int.max).intValueExact() == int.max);
    assert(BigInteger.valueOf(short.min).shortValueExact() == short.min);
    assert(BigInteger.valueOf(short.max).shortValueExact() == short.max);
    assert(BigInteger.valueOf(byte.min).byteValueExact() == byte.min);
    assert(BigInteger.valueOf(byte.max).byteValueExact() == byte.max);
    assert(BigInteger.valueOf(0).longValueExact() == 0);

    // 2^64 plus 255: each narrowing conversion discards the high bits.
    auto twiceWrapped = new BigInteger([1, 0, 0, 0, 0, 0, 0, 0, -1]);
    assert(twiceWrapped.longValue() == 255);
    assert(twiceWrapped.intValue() == 255);
    assert(twiceWrapped.shortValue() == 255);
    assert(twiceWrapped.byteValue() == -1);
    assert(BigInteger.valueOf(65_535).shortValue() == -1);
    assert(BigInteger.valueOf(-129).byteValue() == 127);
}

@("BigInteger exact conversions reject either side of every integral range")
unittest
{
    auto one = new BigInteger([1]);
    auto outsideLong = [
        BigInteger.valueOf(long.min).subtract(one), BigInteger.valueOf(long.max).add(one),
        new BigInteger(1, [1, 0, 0, 0, 0, 0, 0, 0, 0]),
        new BigInteger(-1, [1, 0, 0, 0, 0, 0, 0, 0, 0])
    ];
    foreach (value; outsideLong)
        rejectsOverflow(() { value.longValueExact(); });
    foreach (edge; [cast(long) int.min - 1, cast(long) int.max + 1, 1L << 32, -(1L << 32)])
        rejectsOverflow(() { BigInteger.valueOf(edge).intValueExact(); });
    foreach (edge; [cast(int) short.min - 1, cast(int) short.max + 1])
        rejectsOverflow(() { BigInteger.valueOf(edge).shortValueExact(); });
    foreach (edge; [cast(int) byte.min - 1, cast(int) byte.max + 1])
        rejectsOverflow(() { BigInteger.valueOf(edge).byteValueExact(); });
}

private void rejectsOverflow(scope void delegate() @safe convert)
{
    try
    {
        convert();
        assert(0, "overflow must throw ArithmeticException");
    }
    catch (ArithmeticException)
    {
    }
}
