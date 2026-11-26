module flint.java.math.bigdecimal_parse_tests;

import flint.java.math.internal.decimalparse : DecimalParts, scanDecimal;

@safe:

@("BigDecimal text preserves scale and precision across mixed BMP scripts")
unittest
{
    DecimalParts parts;
    assert(scanDecimal("＋１", parts) == false);
    assert(scanDecimal("+００１٢.٣４００e+٠٢", parts));
    assert(parts.scale == 2 && parts.precision == 6);
    assert(parts.isCompact && parts.compactValue == 123_400 && !parts.negative);
    assert("+００１٢.٣４００e+٠٢"[parts.coefficientStart .. parts.coefficientEnd] == "００１٢.٣４００");

    assert(scanDecimal("-0.000", parts));
    assert(parts.scale == 3 && parts.precision == 1);
    assert(parts.isCompact && parts.compactValue == 0 && !parts.negative);
}

@("BigDecimal accepts any exponent whose resulting scale fits a Java int")
unittest
{
    DecimalParts parts;
    assert(scanDecimal("1e2147483648", parts) && parts.scale == int.min);
    assert(scanDecimal("1e-2147483647", parts) && parts.scale == int.max);
    assert(scanDecimal("1.00e+000000000000000002147483650", parts) && parts.scale == int.min);
    assert(!scanDecimal("1e2147483649", parts));
    assert(!scanDecimal("1e-2147483648", parts));
    assert(!scanDecimal("1.0e-2147483647", parts));
    assert(!scanDecimal("0e9999999999999999999999999999", parts));
}

@("BigDecimal construction widens when the unscaled value exceeds long")
unittest
{
    DecimalParts parts;
    assert(scanDecimal("-9223372036854775808", parts));
    assert(parts.isCompact && parts.compactValue == long.min && parts.negative && parts.precision == 19);
    assert(scanDecimal("9223372036854775808", parts));
    assert(!parts.isCompact && !parts.negative && parts.precision == 19);
    assert(scanDecimal("-12345678901234567890123.0001", parts));
    assert(!parts.isCompact && parts.negative && parts.precision == 27 && parts.scale == 4);
}

@("BigDecimal text rejects malformed separators, empty digits and supplementary characters")
unittest
{
    DecimalParts parts;
    foreach (text; [
        "", ".", "+", "-.", " 1", "1 ", "1_0", "1..0", "1e", "1e+", "1e--2", "e12", "1e1e2",
        "𝟟.0", "1e𝟟", "\xFF", "1\xFF"
    ])
        assert(!scanDecimal(text, parts), text);
    assert(scanDecimal(".1", parts) && parts.compactValue == 1 && parts.scale == 1);
    assert(scanDecimal("1.e2", parts) && parts.compactValue == 1 && parts.scale == -2);
}
