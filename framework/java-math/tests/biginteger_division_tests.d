module biginteger_division_tests;

import flint.java.lang : ArithmeticException, NullPointerException;
import flint.java.math.biginteger : BigInteger;

@safe:

@("BigInteger division truncates toward zero and keeps the dividend's remainder sign")
unittest
{
    foreach (dividend; [-17L, 17L])
    {
        foreach (divisor; [-5L, 5L])
        {
            auto a = BigInteger.valueOf(dividend);
            auto b = BigInteger.valueOf(divisor);
            auto both = a.divideAndRemainder(b);
            assert(both.length == 2);
            assert(both[0].longValueExact() == dividend / divisor);
            assert(both[1].longValueExact() == dividend % divisor);
            assert(a.divide(b).compareTo(both[0]) == 0);
            assert(a.remainder(b).compareTo(both[1]) == 0);
        }
    }
}

@("BigInteger division corrects a quotient guess after subtracting every limb")
unittest
{
    auto divisor = new BigInteger(1, [-128, 0, 0, 1, 1, 2, 3, 4, 0, 0, 0, 3]);
    auto one = BigInteger.valueOf(1);
    auto dividend = divisor.add(divisor).subtract(one);
    auto both = dividend.divideAndRemainder(divisor);
    assert(both[0].compareTo(one) == 0);
    assert(both[1].compareTo(divisor.subtract(one)) == 0);
}

@("BigInteger division distinguishes a zero divisor from a null divisor")
unittest
{
    auto dividend = BigInteger.valueOf(0);
    try
    {
        dividend.divide(BigInteger.valueOf(0));
        assert(0, "zero divisor accepted");
    }
    catch (ArithmeticException)
    {
    }
    try
    {
        dividend.remainder(null);
        assert(0, "null divisor accepted");
    }
    catch (NullPointerException)
    {
    }
}
