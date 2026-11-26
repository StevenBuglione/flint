module flint.java.number_test;

import flint.java.lang.number : Number;

@safe:

private final class CustomNumber : Number
{
    int conversions;

    override int intValue()
    {
        ++conversions;
        return 65_663;
    }

    override long longValue()
    {
        return 65_663;
    }

    override float floatValue()
    {
        return 65_663.0f;
    }

    override double doubleValue()
    {
        return 65_663.0;
    }
}

@("Number narrowing conversions dispatch to the subclass intValue")
unittest
{
    auto custom = new CustomNumber;
    Number value = custom;
    assert(value.byteValue() == 127);
    assert(value.shortValue() == 127);
    assert(custom.conversions == 2);
    assert(value.longValue() == 65_663);
    assert(value.floatValue() == 65_663.0f);
    assert(value.doubleValue() == 65_663.0);
}
