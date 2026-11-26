/// Noncurrency symbol fixtures from Temurin 21.0.13+9.
module flint.java.text.decimalformatsymbols_test;

import flint.java.text.internal.decimalformatsymbols : decimalSymbolData;

@safe:

@("ROOT, English and US share the pinned numeric symbols") unittest
{
    static void check() pure nothrow @nogc
    {
        const root = decimalSymbolData("", "", "");
        assert(root !is null);
        assert(root is decimalSymbolData("en", "", ""));
        assert(root is decimalSymbolData("en", "US", ""));
        assert(root.zeroDigit == '0' && root.digit == '#');
        assert(root.groupingSeparator == ',' && root.decimalSeparator == '.');
        assert(root.monetaryGroupingSeparator == ',' && root.monetaryDecimalSeparator == '.');
        assert(root.perMill == '\u2030' && root.percent == '%');
        assert(root.patternSeparator == ';' && root.minusSign == '-');
        assert(root.infinity == "∞" && root.nan == "NaN" && root.exponentSeparator == "E");
    }

    check();
}

@("An unsupported locale has no numeric symbol data") unittest
{
    assert(decimalSymbolData("fr", "", "") is null);
    assert(decimalSymbolData("en", "ZA", "") is null);
    assert(decimalSymbolData("en", "US", "POSIX") is null);
}
