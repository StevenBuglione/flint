// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/++
`java.text.DecimalFormatSymbols` (clean room, from the Java SE specification): the numeric and currency symbols a
`DecimalFormat` formats and parses with. The pinned data covers ROOT, English and US English; any other locale is
rejected by name rather than silently formatted with the wrong symbols.
+/
module flint.java.text.decimalformatsymbols;

import flint.java.lang : IllegalArgumentException;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, decimalSymbolData;
import flint.java.util : Locale;

@safe:

/// Java's `DecimalFormatSymbols`: a copy of the pinned locale's symbols, which setters may change.
class DecimalFormatSymbols
{
    private DecimalSymbolData data;

    /// The symbols of `locale`. Throws `IllegalArgumentException` for a locale without pinned data.
    this(Locale locale = Locale.getDefault())
    {
        const DecimalSymbolData* symbols = decimalSymbolData(locale.getLanguage(),
                locale.getCountry(), locale.getVariant());
        if (symbols is null)
            fail("unsupported DecimalFormatSymbols locale");
        data = *symbols;
    }

    /// A copy of `other`; the copy is independent of the original.
    this(const DecimalFormatSymbols other) pure nothrow
    {
        data = other.data;
    }

    /// The symbols for a raw pinned-data record, for the DecimalFormat in this package.
    package(flint.java.text) this(DecimalSymbolData symbols) pure nothrow @nogc
    {
        data = symbols;
    }

    /// The raw symbol data, for the DecimalFormat renderers in this package.
    package(flint.java.text) const(DecimalSymbolData)* raw() const pure nothrow @nogc
    {
        return &data;
    }

    /// The one construction site for this class: every factory and copy funnels through it.
    private static DecimalFormatSymbols make(DecimalSymbolData symbols) @safe
    {
        return new DecimalFormatSymbols(symbols);
    }

    private static void fail(string message) @safe
    {
        throw new IllegalArgumentException(message);
    }

    /// The symbols for a raw pinned-data record, for the DecimalFormat in this package.
    package(flint.java.text) static DecimalFormatSymbols from(DecimalSymbolData symbols) @safe
    {
        return make(symbols);
    }

    /// Java's `DecimalFormatSymbols.getInstance(locale)`.
    static DecimalFormatSymbols getInstance(Locale locale = Locale.getDefault())
    {
        const DecimalSymbolData* symbols = decimalSymbolData(locale.getLanguage(),
                locale.getCountry(), locale.getVariant());
        if (symbols is null)
            fail("unsupported DecimalFormatSymbols locale");
        return make(*symbols);
    }

    /// The zero digit.
    wchar getZeroDigit() const pure nothrow @nogc
    {
        return data.zeroDigit;
    }

    /// Set the zero digit.
    void setZeroDigit(wchar value) pure nothrow @nogc
    {
        data.zeroDigit = value;
    }

    /// The decimal separator.
    wchar getDecimalSeparator() const pure nothrow @nogc
    {
        return data.decimalSeparator;
    }

    /// The grouping separator.
    wchar getGroupingSeparator() const pure nothrow @nogc
    {
        return data.groupingSeparator;
    }

    /// The per-mille sign.
    wchar getPerMill() const pure nothrow @nogc
    {
        return data.perMill;
    }

    /// The percent sign.
    wchar getPercent() const pure nothrow @nogc
    {
        return data.percent;
    }

    /// The digit placeholder.
    wchar getDigit() const pure nothrow @nogc
    {
        return data.digit;
    }

    /// The pattern separator.
    wchar getPatternSeparator() const pure nothrow @nogc
    {
        return data.patternSeparator;
    }

    /// The minus sign.
    wchar getMinusSign() const pure nothrow @nogc
    {
        return data.minusSign;
    }

    /// The monetary decimal separator.
    wchar getMonetaryDecimalSeparator() const pure nothrow @nogc
    {
        return data.monetaryDecimalSeparator;
    }

    /// The monetary grouping separator.
    wchar getMonetaryGroupingSeparator() const pure nothrow @nogc
    {
        return data.monetaryGroupingSeparator;
    }

    /// The exponent separator.
    string getExponentSeparator() const pure nothrow @nogc
    {
        return data.exponentSeparator;
    }

    /// The infinity string.
    string getInfinity() const pure nothrow @nogc
    {
        return data.infinity;
    }

    /// The NaN string.
    string getNaN() const pure nothrow @nogc
    {
        return data.nan;
    }

    /// The currency symbol.
    string getCurrencySymbol() const pure nothrow @nogc
    {
        return data.currencySymbol;
    }

    /// The international currency symbol.
    string getInternationalCurrencySymbol() const pure nothrow @nogc
    {
        return data.internationalCurrencySymbol;
    }

    /// A copy of the symbols, for `DecimalFormat.getDecimalFormatSymbols`.
    DecimalFormatSymbols copy() const @safe
    {
        return make(data);
    }
}
