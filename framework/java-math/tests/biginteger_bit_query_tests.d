module biginteger_bit_query_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("Signed bit lengths cross limb boundaries") unittest
{
    const zero = BigInteger.valueOf(0);
    const negativeOne = BigInteger.valueOf(-1);
    const negativeMinimum = BigInteger.valueOf(long.min);
    assert(zero.bitLength() == 0);
    assert(negativeOne.bitLength() == 0);
    assert(negativeMinimum.bitLength() == 63);

    static immutable byte[] twoWords = [1, 0, 0, 0, 2, 0, 0, 0, 0];
    const positive = new BigInteger(1, twoWords);
    const negative = new BigInteger(-1, twoWords);
    assert(positive.bitLength() == 65 && negative.bitLength() == 65);
}

private int queryBitLength(scope const BigInteger value) pure nothrow @nogc
{
    return value.bitLength();
}

@("Bit length is available to allocation-free callers") unittest
{
    assert(queryBitLength(BigInteger.valueOf(32)) == 6);
}
