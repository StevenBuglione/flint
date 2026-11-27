/// DecimalFormat localized patterns and the separator-free negative reading, checked against Temurin 21.0.13+9
/// (decimal-localized/unit-rows.tsv).
module flint.java.text.decimal_localized_test;

import flint.java.text.internal.decimalfixed : DecimalField, DecimalFixedPattern;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, localizedPatternSymbolsEncodable;
import flint.java.text.internal.decimalpattern : compileFixedDecimalPattern,
    compileLocalizedDecimalPattern, DecimalCompileStatus;

@safe:

private DecimalSymbolData german() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.groupingSeparator = '.';
    symbols.decimalSeparator = ',';
    return symbols;
}

// Localized symbols that are nonlocalized specials in other roles.
private DecimalSymbolData crossed() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.zeroDigit = '#';
    symbols.groupingSeparator = '.';
    symbols.decimalSeparator = ',';
    symbols.minusSign = ';';
    symbols.percent = '-';
    symbols.perMill = '%';
    symbols.digit = '0';
    symbols.patternSeparator = 'E';
    symbols.exponentSeparator = "e";
    return symbols;
}

private DecimalSymbolData arabic() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.zeroDigit = '٠';
    symbols.groupingSeparator = '٬';
    symbols.decimalSeparator = '٫';
    symbols.minusSign = '−';
    symbols.percent = '٪';
    symbols.perMill = '؉';
    symbols.digit = '•';
    symbols.patternSeparator = '؛';
    symbols.exponentSeparator = "×١٠^";
    return symbols;
}

private struct Row
{
    string pattern;
    string positivePrefix;
    string positiveSuffix;
    string negativePrefix;
    string negativeSuffix;
    uint minimumIntegerDigits;
    uint maximumFractionDigits;
    uint groupingSize;
    ubyte minimumExponentDigits;
    ubyte scale;
}

private void check(ref const DecimalSymbolData symbols, Row row, bool localized = true) pure nothrow
{
    DecimalFixedPattern pattern;
    const status = localized ? compileLocalizedDecimalPattern(row.pattern, symbols, pattern)
        : compileFixedDecimalPattern(row.pattern, symbols, pattern);
    assert(status == DecimalCompileStatus.accepted);
    assert(pattern.positive.prefix == row.positivePrefix && pattern.positive.suffix == row.positiveSuffix);
    assert(pattern.negative.prefix == row.negativePrefix && pattern.negative.suffix == row.negativeSuffix);
    assert(pattern.minimumIntegerDigits == row.minimumIntegerDigits);
    assert(pattern.maximumFractionDigits == row.maximumFractionDigits);
    assert(pattern.groupingSize == row.groupingSize);
    assert(pattern.minimumExponentDigits == row.minimumExponentDigits && pattern.scale == row.scale);
}

private DecimalCompileStatus localizedStatus(string text, ref const DecimalSymbolData symbols) pure nothrow
{
    DecimalFixedPattern pattern;
    return compileLocalizedDecimalPattern(text, symbols, pattern);
}

@("German symbols swap the grouping and decimal pattern characters") unittest
{
    const symbols = german();
    check(symbols, Row("#.##0,00", "", "", "-", "", 1, 2, 3));
    // A quoted nonlocalized-looking character stays literal.
    check(symbols, Row("'.'0,0", ".", "", "-.", "", 1, 1));
}

@("Localized symbols take Java's precedence over the nonlocalized specials") unittest
{
    const symbols = crossed();
    assert(localizedStatus("0.##0,#", symbols) == DecimalCompileStatus.malformed);
    // E separates the subpatterns; the negative suffix's `-` is the percent sign.
    check(symbols, Row("#E#-", "", "", "", "-", 1, 0, 0, 0, 0));
    check(symbols, Row("'0'#", "0", "", ";0", "", 1, 0));

    DecimalSymbolData quote;
    quote.minusSign = '¤';
    quote.percent = 'x';
    quote.digit = '\'';
    quote.patternSeparator = ' ';
    quote.exponentSeparator = "^";
    // An unquoted apostrophe is the digit symbol, checked before quoting.
    check(quote, Row("'0", "", "", "¤", "", 1, 0));
    check(quote, Row("''0", "", "", "¤", "", 1, 0));
    check(quote, Row("0x", "", "x", "¤", "x", 1, 0, 0, 0, 2));
}

@("Multi-byte symbols and a multi-unit exponent") unittest
{
    const symbols = arabic();
    check(symbols, Row("•٬••٠٫٠٠", "", "", "−", "", 1, 2, 3));
    check(symbols, Row("٠٫٠×١٠^٠٠", "", "", "−", "", 1, 1, 0, 2));
    assert(localizedStatus("٠×١٠^", symbols) == DecimalCompileStatus.malformed);

    DecimalSymbolData wide;
    wide.zeroDigit = '０';
    wide.groupingSeparator = ' ';
    wide.decimalSeparator = '·';
    wide.minusSign = '−';
    wide.digit = '*';
    wide.patternSeparator = 'x';
    wide.exponentSeparator = "x😀";
    check(wide, Row("*０x😀０", "", "", "−", "", 1, 0, 0, 1));
    // `x-` is not the exponent, so x separates the subpatterns.
    check(wide, Row("０x-０", "", "", "-", "", 1, 0));
}

@("Colliding localized symbols resolve in Java's order") unittest
{
    DecimalSymbolData symbols;
    symbols.decimalSeparator = ',';
    symbols.minusSign = '%';
    symbols.perMill = '%';
    symbols.exponentSeparator = "ee";
    // Grouping wins over decimal, percent over per-mille and minus.
    check(symbols, Row("#,##0,0", "", "", "%", "", 2, 0, 1));
    check(symbols, Row("0%", "", "%", "%", "%", 1, 0, 0, 0, 2));
    check(symbols, Row("0ee0ee", "", "ee", "", "", 1, 0, 0, 1));
}

@("An empty exponent separator rejects any suffix, so the negative reading never loops") unittest
{
    DecimalSymbolData symbols;
    symbols.exponentSeparator = "";
    assert(localizedStatus("0x", symbols) == DecimalCompileStatus.malformed);
    assert(localizedStatus("0;-0", symbols) == DecimalCompileStatus.malformed);
    check(symbols, Row("00", "", "", "-", "", 2, 0));
}

@("Java's immediate exponent errors are not deferred by a later digit") unittest
{
    const DecimalSymbolData symbols;
    assert(localizedStatus("0E", symbols) == DecimalCompileStatus.malformed);
    assert(localizedStatus(".E0", symbols) == DecimalCompileStatus.malformed);
    assert(localizedStatus("0E0#0E0", symbols) == DecimalCompileStatus.malformed);
    assert(localizedStatus(".E0x0", symbols) == DecimalCompileStatus.malformed);
    assert(localizedStatus("0Ex0", symbols) == DecimalCompileStatus.malformed);
}

private string exponentZeros(size_t count, string tail) pure nothrow
{
    string text = "0E";
    foreach (_; 0 .. count)
        text ~= '0';
    return text ~ tail;
}

@("The exponent's zero count wraps like Java's byte, so 128 to 256 zeros throw at once") unittest
{
    const DecimalSymbolData symbols;
    assert(localizedStatus(exponentZeros(127, "x"), symbols) == DecimalCompileStatus.accepted);
    foreach (count; [128, 129, 255, 256])
        foreach (tail; ["", "#", "x"])
            assert(localizedStatus(exponentZeros(count, tail), symbols) == DecimalCompileStatus.malformed);
    // 257 zeros wrap to one exponent digit.
    check(symbols, Row(exponentZeros(257, "x"), "", "x", "-", "x", 1, 0, 0, 1));
    check(symbols, Row(exponentZeros(257, "x"), "", "x", "-", "x", 1, 0, 0, 1), false);
}

@("Quotes, doubled quotes and the currency pair survive the rewrite") unittest
{
    const DecimalSymbolData symbols;
    check(symbols, Row("'a''b'0'c'", "a'b", "c", "-a'b", "c", 1, 0));
    check(symbols, Row("''''0", "''", "", "-''", "", 1, 0));
    check(symbols, Row("¤'¤'0", "XXX", "", "-XXX", "", 1, 0));
    check(symbols, Row("a-0", "a-", "", "-a-", "", 1, 0));
    DecimalFixedPattern pattern;
    assert(compileLocalizedDecimalPattern("a-0", symbols, pattern) == DecimalCompileStatus.accepted);
    assert(pattern.positive.prefixFields == [DecimalField.sign, 1, 2]);
    assert(localizedStatus("0'x", symbols) == DecimalCompileStatus.malformed);
}

@("A digit symbol equal to the zero digit takes precedence") unittest
{
    DecimalSymbolData symbols;
    symbols.digit = '0';
    check(symbols, Row("00.0", "", "", "-", "", 1, 1));
    check(symbols, Row("#00", "#", "", "-#", "", 0, 0));
}

@("Without a separator the negative reading skips exponent symbols") unittest
{
    const DecimalSymbolData symbols;
    foreach (localized; [false, true])
    {
        check(symbols, Row("0E0E", "", "E", "", "", 1, 0, 0, 1), localized);
        check(symbols, Row("0E0", "", "", "-", "", 1, 0, 0, 1), localized);
        check(symbols, Row("abc", "abc", "", "-abc", "", 0, 0), localized);
    }
    check(symbols, Row("0E0E x", "", "E x", "", " x", 1, 0, 0, 1), false);
    check(symbols, Row("0E0'E'", "", "E", "-", "E", 1, 0, 0, 1));

    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern("0E0E", symbols, pattern) == DecimalCompileStatus.accepted);
    assert(pattern.negative.prefixFields.length == 0);
}

@("The digit and pattern separator must be scalars for a localized pattern") unittest
{
    DecimalSymbolData symbols;
    assert(localizedPatternSymbolsEncodable(symbols));
    symbols.digit = cast(wchar) 0xD83D;
    assert(!localizedPatternSymbolsEncodable(symbols));
    symbols.digit = '#';
    symbols.patternSeparator = cast(wchar) 0xDC00;
    assert(!localizedPatternSymbolsEncodable(symbols));
}
