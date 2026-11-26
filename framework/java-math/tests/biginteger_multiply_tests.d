module biginteger_multiply_tests;

import flint.java.lang : ArithmeticException;
import flint.java.math.biginteger : BigInteger;
import std.exception : assertThrown;

@safe:

@("Full limbs carry across the entire product")
unittest
{
    auto value = new BigInteger(1, [-1, -1, -1, -1, -1, -1, -1, -1]);
    assert(value.multiply(value).toByteArray() == [
        0, -1, -1, -1, -1, -1, -1, -1, -2, 0, 0, 0, 0, 0, 0, 0, 1
    ]);
}

@("BigInteger exponentiation handles zero and rejects out-of-range powers before allocation")
unittest
{
    assert(BigInteger.valueOf(0).pow(0).intValueExact() == 1);
    assert(BigInteger.valueOf(0).pow(int.max).signum() == 0);
    assert(BigInteger.valueOf(-1).pow(int.max).intValueExact() == -1);
    assert(BigInteger.valueOf(-1).pow(int.max - 1).intValueExact() == 1);
    auto power = BigInteger.valueOf(-16).pow(25);
    assert(power.signum() == -1);
    assert(power.toString(16) == "-10000000000000000000000000");
    try
    {
        BigInteger.valueOf(2).pow(int.max);
        assert(0, "power exceeds the supported range");
    }
    catch (ArithmeticException)
    {
    }
}

@("BigInteger rejects negative powers")
unittest
{
    foreach (base; [-23, 0, 23])
        assertThrown!ArithmeticException(BigInteger.valueOf(base).pow(-1));
}
