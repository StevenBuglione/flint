module biginteger_product_columns_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("Full-word products carry across many output columns") unittest
{
    foreach (width; [17, 33, 65])
    {
        auto input = new byte[width];
        input[] = -1;
        auto expected = new byte[2 * width + 1];
        expected[1 .. width + 1] = -1;
        expected[width] = -2;
        expected[$ - 1] = 1;

        auto value = new BigInteger(1, input);
        assert(value.multiply(value).toByteArray() == expected);
    }
}

@("Highly uneven products expose the first and last diagonal") unittest
{
    auto input = new byte[33];
    input[] = -1;
    auto expected = new byte[input.length + 2];
    expected[1] = -2;
    expected[2 .. $ - 1] = -1;
    expected[$ - 1] = 1;

    auto value = new BigInteger(1, input);
    auto factor = BigInteger.valueOf(255);
    assert(value.multiply(factor).toByteArray() == expected);
    assert(factor.multiply(value).toByteArray() == expected);
}
