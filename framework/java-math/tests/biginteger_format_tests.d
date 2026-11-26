module biginteger_format_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("BigInteger string conversion defaults to signed decimal")
unittest
{
    auto value = new BigInteger(-1, [1, 35, 69, 103, -119, -85, -51, -17, 1]);
    assert(value.toString() == "-20988295479420645121");
    assert(BigInteger.valueOf(long.min).toString() == "-9223372036854775808");
    assert(value.toString(1) == value.toString());
    assert(value.toString(37) == value.toString());
    assert(BigInteger.valueOf(0).toString(36) == "0");
}

@("BigInteger formats limbs across radix digit and group boundaries")
unittest
{
    auto value = new BigInteger([1, 35, 69, 103, -119, -85, -51, -17, 1]);
    assert(value.toString(2) == "10010001101000101011001111000100110101011110011011110111100000001");
    assert(value.toString(3) == "12011211111210200010022111201210012101221");
    assert(value.toString(16) == "123456789abcdef01");
    assert(value.toString(24) == "nmgk09kegc5eg1");
    assert(value.toString(32) == "i6hb7h6lsrro1");
    assert(value.toString(36) == "4fgj5t7fghnup");

    auto power = BigInteger.valueOf(1);
    auto base = BigInteger.valueOf(36);
    foreach (i; 0 .. 18)
        power = power.multiply(base);
    assert(power.toString(36) == "1000000000000000000");
}
