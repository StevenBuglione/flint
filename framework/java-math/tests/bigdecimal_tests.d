module bigdecimal_tests;

import flint.java.lang : NumberFormatException;
import flint.java.lang.number : Number;
import flint.java.math.bigdecimal : BigDecimal;
import std.exception : assertThrown;

@safe:

@("BigDecimal owns its coefficient and preserves the Java precision and signed scale")
unittest
{
    auto buffer = "-０01234567890123456789.00E+6".dup;
    auto value = new BigDecimal(buffer);
    buffer[] = '0';
    assert(value.scale() == -4);
    assert(value.precision() == 21);
    assert(value.signum() == -1);
    assert(value.unscaledValue().toString() == "-123456789012345678900");

    auto zero = new BigDecimal("-0.000E+9");
    assert(zero.scale() == -6);
    assert(zero.precision() == 1);
    assert(zero.signum() == 0);
    assert(zero.unscaledValue().signum() == 0);
}

@("BigDecimal rejects malformed text and null and empty slices through the same boundary")
unittest
{
    assertThrown!NumberFormatException(new BigDecimal(""));
    assertThrown!NumberFormatException(new BigDecimal(null));
    assertThrown!NumberFormatException(new BigDecimal("1E-2147483648"));
    assertThrown!NumberFormatException(new BigDecimal(" 1.00"));
    assertThrown!NumberFormatException(new BigDecimal("𝟚"));
}

@("BigDecimal implements Number and preserves the low bits after decimal truncation")
unittest
{
    Number value = new BigDecimal("18446744073709551629.6");
    assert(value.longValue() == 13);
    assert(value.intValue() == 13);
    assert(value.byteValue() == 13 && value.shortValue() == 13);
    assert((new BigDecimal("-1.999")).longValue() == -1);
    assert((new BigDecimal("-18446744073709551629.6")).longValue() == -13);
    assert((new BigDecimal("18446744073709551617E+2")).longValue() == 100);
    assert((new BigDecimal("2147483648.99")).intValue() == int.min);
    assert((new BigDecimal("1E-2147483647")).longValue() == 0);
    assert((new BigDecimal("-1E+2147483648")).longValue() == 0);
    assert((new BigDecimal("-9223372036854775808")).longValue() == long.min);
}

@("BigDecimal rounds directly to each binary format and preserves the sign of underflow")
unittest
{
    assert((new BigDecimal("1.000000059604644775390625")).floatValue() == 1.0f);
    assert((new BigDecimal("1.0000000596046447753906251")).floatValue() == 0x1.000002p0f);
    const midpoint = "1.00000000000000011102230246251565404236316680908203125";
    assert((new BigDecimal(midpoint)).doubleValue() == 1.0);
    assert((new BigDecimal(midpoint ~ "1")).doubleValue() == 0x1.0000000000001p0);
    assert(1.0f / (new BigDecimal("-1E-999")).floatValue() == -float.infinity);
    assert(1.0 / (new BigDecimal("-1E-999")).doubleValue() == -double.infinity);
    assert((new BigDecimal("3.5E+38")).floatValue() == float.infinity);
    assert((new BigDecimal("-1.8E+308")).doubleValue() == -double.infinity);
    assert((new BigDecimal("1E+2147483648")).doubleValue() == double.infinity);
}
