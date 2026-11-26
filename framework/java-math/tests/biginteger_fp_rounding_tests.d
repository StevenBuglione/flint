module biginteger_fp_rounding_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("BigInteger primitive floats round halfway values to even")
unittest
{
    assert(BigInteger.valueOf(16_777_217).floatValue() == 16_777_216.0f);
    assert(BigInteger.valueOf(-16_777_219).floatValue() == -16_777_220.0f);
    assert(BigInteger.valueOf(9_007_199_254_740_993).doubleValue() == 9_007_199_254_740_992.0);
    assert(BigInteger.valueOf(-9_007_199_254_740_995).doubleValue() == -9_007_199_254_740_996.0);
}

@("BigInteger float rounding observes bits below double precision")
unittest
{
    auto tie = powerOfTwo(80).add(powerOfTwo(56));
    assert(tie.floatValue() == 0x1p80f);
    assert(tie.add(BigInteger.valueOf(1)).floatValue() == 0x1.000002p80f);
}

@("BigInteger rounds to the largest finite value and to infinity at the overflow midpoint")
unittest
{
    auto one = BigInteger.valueOf(1);
    auto zero = BigInteger.valueOf(0);
    auto floatMidpoint = powerOfTwo(128).subtract(powerOfTwo(103));
    assert(floatMidpoint.subtract(one).floatValue() == float.max);
    assert(floatMidpoint.floatValue() == float.infinity);
    assert(zero.subtract(floatMidpoint).floatValue() == -float.infinity);
    auto doubleMidpoint = powerOfTwo(1_024).subtract(powerOfTwo(970));
    assert(doubleMidpoint.subtract(one).doubleValue() == double.max);
    assert(doubleMidpoint.doubleValue() == double.infinity);
    assert(zero.subtract(doubleMidpoint).doubleValue() == -double.infinity);
}

private BigInteger powerOfTwo(uint exponent)
{
    byte[129] bytes;
    bytes[0] = cast(byte)(1U << (exponent % 8));
    return new BigInteger(1, bytes[0 .. exponent / 8 + 1]);
}
