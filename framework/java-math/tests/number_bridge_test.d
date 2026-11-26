module flint.java.math.number_bridge_test;

import flint.java.lang.number : Number;
import flint.java.math.biginteger : BigInteger;

@safe:

@("BigInteger satisfies the Number contract without changing const conversion callers")
unittest
{
    const BigInteger fixed = BigInteger.valueOf(65_663);
    assert(fixed.intValue() == 65_663);
    Number base = BigInteger.valueOf(65_663);
    assert(base.intValue() == 65_663);
    assert(base.longValue() == 65_663);
    assert(base.shortValue() == 127);
    assert(base.byteValue() == 127);
    assert(base.floatValue() == 65_663.0f);
    assert(base.doubleValue() == 65_663.0);
}
