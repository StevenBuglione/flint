/// Numeric symbol fixtures from Temurin 21.0.13+9; decimal_currency_test covers the currency fields.
module flint.java.text.decimalformatsymbols_test;

import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, decimalSymbolData;

@safe:

@("ROOT, English and US share the pinned numeric symbols") unittest
{
    static void check(const(DecimalSymbolData)* root) pure nothrow @nogc
    {
        assert(root !is null);
        assert(root.zeroDigit == '0' && root.digit == '#');
        assert(root.groupingSeparator == ',' && root.decimalSeparator == '.');
        assert(root.monetaryGroupingSeparator == ',' && root.monetaryDecimalSeparator == '.');
        assert(root.perMill == '\u2030' && root.percent == '%');
        assert(root.patternSeparator == ';' && root.minusSign == '-');
        assert(root.infinity == "∞" && root.nan == "NaN" && root.exponentSeparator == "E");
    }

    assert(decimalSymbolData("", "", "") is decimalSymbolData("en", "", ""));
    check(decimalSymbolData("", "", ""));
    check(decimalSymbolData("en", "US", ""));
}

@("An unsupported locale has no numeric symbol data") unittest
{
    assert(decimalSymbolData("fr", "", "") is null);
    assert(decimalSymbolData("en", "ZA", "") is null);
    assert(decimalSymbolData("en", "US", "POSIX") is null);
}
