module biginteger_equality_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("Value equality across encodings and D keys") unittest
{
    auto positive = BigInteger.valueOf(0x1_FFFF_FFFFL);
    auto equal = new BigInteger(1, [0, 1, -1, -1, -1, -1]);
    auto negative = BigInteger.valueOf(-0x1_FFFF_FFFFL);
    assert(positive !is equal && positive == equal);
    assert(positive != negative);
    assert(positive.hashCode() == 30);
    assert(negative.hashCode() == -30);
    assert(equal.hashCode() == positive.hashCode());

    int[BigInteger] values;
    values[positive] = 3;
    assert(values[equal] == 3);
    values[negative] = 4;
    assert(values.length == 2);
    assert(values[negative] == 4);
}

@("Zero and unsigned limbs have stable hashes") unittest
{
    const zero = new BigInteger(-1, [0, 0]);
    assert(zero.equals(BigInteger.valueOf(0)));
    assert(zero.hashCode() == 0);

    const unsignedWord = new BigInteger(1, [-128, 0, 0, 0]);
    assert(unsignedWord.hashCode() == int.min);
}
