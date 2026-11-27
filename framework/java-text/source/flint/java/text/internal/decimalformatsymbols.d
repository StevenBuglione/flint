// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Numeric and currency symbol data verified against Temurin 21.0.13+9.
module flint.java.text.internal.decimalformatsymbols;

@safe:

package(flint.java.text) struct DecimalSymbolData
{
    wchar zeroDigit = '0';
    wchar groupingSeparator = ',';
    wchar decimalSeparator = '.';
    wchar perMill = '\u2030';
    wchar percent = '%';
    wchar digit = '#';
    wchar patternSeparator = ';';
    wchar minusSign = '-';
    wchar monetaryDecimalSeparator = '.';
    wchar monetaryGroupingSeparator = ',';
    string infinity = "∞";
    string nan = "NaN";
    string exponentSeparator = "E";
    // A locale without a region has no currency: Java shows the generic sign and the XXX code.
    string currencySymbol = "¤";
    string internationalCurrencySymbol = "XXX";
}

private immutable DecimalSymbolData latinSymbols;
private immutable DecimalSymbolData unitedStatesSymbols = () {
    DecimalSymbolData symbols;
    symbols.currencySymbol = "$";
    symbols.internationalCurrencySymbol = "USD";
    return symbols;
}();

/// Shared data for the supported explicit locales; ROOT and English share it, and US adds its currency.
/// Use the language, region and variant of an explicit locale. Unsupported profiles have no entry.
package(flint.java.text) const(DecimalSymbolData)* decimalSymbolData(scope string language,
        scope string region, scope string variant) pure nothrow @nogc
{
    if (variant.length != 0)
        return null;
    if ((language.length == 0 && region.length == 0) || (language == "en" && region.length == 0))
        return &latinSymbols;
    return language == "en" && region == "US" ? &unitedStatesSymbols : null;
}

/// Writes the UTF-8 form of one UTF-16 symbol unit and returns its width.
/// A lone surrogate has no UTF-8 form; callers check `bodySymbolsEncodable` first.
size_t encodeSymbol(wchar unit, ref scope char[3] output) pure nothrow @nogc
in (unit < 0xD800 || unit > 0xDFFF)
{
    if (unit < 0x80)
    {
        output[0] = cast(char) unit;
        return 1;
    }
    if (unit < 0x800)
    {
        output[0] = cast(char)(0xC0 | (unit >> 6));
        output[1] = cast(char)(0x80 | (unit & 0x3F));
        return 2;
    }
    output[0] = cast(char)(0xE0 | (unit >> 12));
    output[1] = cast(char)(0x80 | ((unit >> 6) & 0x3F));
    output[2] = cast(char)(0x80 | (unit & 0x3F));
    return 3;
}

/// Java writes each digit as the 16-bit sum of the zero digit and its value, and the separators (monetary ones
/// for a currency pattern), minus, percent and per-mille signs as single UTF-16 units. The UTF-8 renderer
/// requires all of them to be scalars.
bool bodySymbolsEncodable(ref scope const DecimalSymbolData symbols) pure nothrow @nogc
{
    foreach (digit; 0 .. 10)
        if (isSurrogate(cast(wchar)(symbols.zeroDigit + digit)))
            return false;
    return !isSurrogate(symbols.groupingSeparator) && !isSurrogate(symbols.decimalSeparator)
        && !isSurrogate(symbols.monetaryGroupingSeparator)
        && !isSurrogate(symbols.monetaryDecimalSeparator) && !isSurrogate(symbols.minusSign)
        && !isSurrogate(symbols.percent) && !isSurrogate(symbols.perMill);
}

/// applyLocalizedPattern also matches the digit and pattern separator symbols against single UTF-16 units of
/// the pattern; a UTF-8 pattern holds no lone surrogate to match.
bool localizedPatternSymbolsEncodable(ref scope const DecimalSymbolData symbols) pure nothrow @nogc
{
    return bodySymbolsEncodable(symbols) && !isSurrogate(symbols.digit) && !isSurrogate(symbols.patternSeparator);
}

private bool isSurrogate(wchar unit) pure nothrow @nogc
{
    return unit >= 0xD800 && unit <= 0xDFFF;
}
