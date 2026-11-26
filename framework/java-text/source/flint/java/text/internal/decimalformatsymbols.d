// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Numeric symbol data verified against Temurin 21.0.13+9.
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
}

private immutable DecimalSymbolData latinSymbols;

/// Shared noncurrency data for the supported explicit locales.
/// Use the language, region and variant of an explicit locale. Unsupported profiles have no entry.
package(flint.java.text) const(DecimalSymbolData)* decimalSymbolData(scope string language,
        scope string region, scope string variant) pure nothrow @nogc
{
    if (variant.length == 0 && ((language.length == 0 && region.length == 0) || (language == "en"
            && (region.length == 0 || region == "US"))))
        return &latinSymbols;
    return null;
}
