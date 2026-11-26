module biginteger_limb_boundary_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("A carry and borrow propagate through a partially filled leading word") unittest
{
    foreach (byteCount; [3, 4, 5, 7, 8, 9, 17])
    {
        auto ones = new byte[byteCount];
        ones[] = -1;
        auto bytes = new byte[byteCount + 1];
        bytes[0] = 1;

        auto one = BigInteger.valueOf(1);
        auto below = new BigInteger(1, ones);
        auto boundary = new BigInteger(bytes);
        assert(below.add(one).equals(boundary));
        assert(boundary.subtract(one).equals(below));
        assert(one.subtract(boundary).equals(below.negate()));
        assert(below.negate().subtract(one).equals(boundary.negate()));
    }
}

@("Redundant signed bytes normalize at sign and word boundaries") unittest
{
    foreach (zeros; [0, 1, 3, 4, 7, 8, 12])
    {
        auto bits = new byte[zeros + 1];
        bits[0] = -128;
        auto extended = new byte[zeros + 4];
        extended[0 .. 3] = -1;
        extended[3 .. $] = bits;
        auto decoded = new BigInteger(extended);
        assert(decoded.signum() == -1);
        assert(decoded.toByteArray() == bits);
        assert(decoded.equals(new BigInteger(bits)));

        auto positive = new byte[zeros + 4];
        positive[3 .. $] = bits;
        assert(new BigInteger(positive).toByteArray() == positive[2 .. $]);
    }
}
