module flint.java.text.internal.decimal_symbols_test;

import flint.java.text.internal.decimalbig : DecimalBigStatus, renderBigDecimal;
import flint.java.text.internal.decimalexponent : renderExponentLong;
import flint.java.text.internal.decimalfixed : DecimalFieldSpan, DecimalFieldSpans,
    DecimalFixedPattern, renderDecimalLong;
import flint.java.text.internal.decimalfixedbinary : tryRenderDecimalDouble;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, bodySymbolsEncodable;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

// Expected text and spans are pinned Temurin 21.0.13+9 results for symbols set through the public
// DecimalFormatSymbols setters on a ROOT instance; spans are UTF-8 byte offsets in field order integer, fraction,
// grouping separator, decimal separator, exponent symbol, exponent sign, exponent, sign, percent, per-mille.
private enum DecimalFieldSpan none = DecimalFieldSpan.init;

private DecimalFieldSpan span(size_t begin, size_t end)
{
    return DecimalFieldSpan(begin, end, true);
}

private DecimalSymbolData symbols(wchar zero, wchar grouping, wchar decimal, wchar minus, wchar percent,
        wchar perMill, string exponent)
{
    DecimalSymbolData result;
    result.zeroDigit = zero;
    result.groupingSeparator = grouping;
    result.decimalSeparator = decimal;
    result.minusSign = minus;
    result.percent = percent;
    result.perMill = perMill;
    result.exponentSeparator = exponent;
    return result;
}

private DecimalFixedPattern compiled(string text, ref const DecimalSymbolData data)
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern(text, data, pattern) == DecimalCompileStatus.accepted);
    return pattern;
}

private void expectLong(string patternText, ref const DecimalSymbolData data, int multiplier, long value,
        string expected, DecimalFieldSpan[10] spans)
{
    const pattern = compiled(patternText, data);
    char[96] output;
    DecimalFieldSpans fields;
    FixedRoundingStatus status;
    size_t required;
    if (pattern.minimumExponentDigits != 0)
        required = renderExponentLong(value, multiplier, pattern, data, output[],
                FixedRoundingMode.halfEven, status, &fields);
    else
        required = renderDecimalLong(value, multiplier, pattern, data, output[], &fields);
    assert(output[0 .. required] == expected);
    assert(fields.spans[] == spans[]);
    if (pattern.minimumExponentDigits != 0)
        return;
    // A buffer one byte short is left untouched and reports the same size.
    char[96] short_ = 'x';
    assert(renderDecimalLong(value, multiplier, pattern, data, short_[0 .. required - 1]) == required);
    foreach (unit; short_)
        assert(unit == 'x');
}

// Digits 0-7 of a U+07F8 zero are two UTF-8 bytes and 8-9 are three; the grouping separator is three bytes.
unittest
{
    const data = symbols('\u07f8', '\u202f', '\u00b7', '\u2012', 'p', 'm', "\u1d07");
    assert(bodySymbolsEncodable(data));
    expectLong("#,##0.###", data, 1, -1_234_567,
            "\u2012\u07f9\u202f\u07fa\u07fb\u07fc\u202f\u07fd\u07fe\u07ff", [
                span(3, 23), span(23, 23), span(5, 8), none, none, none, none, span(0, 3), none, none
    ]);
    expectLong("#,##0.###", data, 1, 999_999, "\u0801\u0801\u0801\u202f\u0801\u0801\u0801",
            [span(0, 21), span(21, 21), span(9, 12), none, none, none, none, none, none, none]);

    const pattern = compiled("0.00E00", data);
    char[64] output;
    size_t required;
    FixedRoundingStatus status;
    DecimalFieldSpans fields;
    assert(tryRenderDecimalDouble(0, 1, pattern, data, output[], required,
            FixedRoundingMode.halfEven, status, &fields));
    assert(output[0 .. required] == "\u07f8\u00b7\u07f8\u07f8\u1d07\u07f8\u07f8");
    assert(fields.spans[] == [
        span(0, 2), span(4, 8), none, span(2, 4), span(8, 11), none, span(11, 15), none, none, none
    ]);
}

// Java's digit arithmetic wraps at 16 bits: a U+FFF8 zero writes 8 and 9 as U+0000 and U+0001.
unittest
{
    const data = symbols('\ufff8', '\'', '\u3002', '\u30fc', '\uff05', '\u2031', "");
    expectLong("#,##0.###", data, 1, 123_456_789_012_345_678,
            "\ufff9\ufffa\ufffb'\ufffc\ufffd\ufffe'\uffff\u0000\u0001'\ufff8\ufff9\ufffa'\ufffb\ufffc\ufffd'"
            ~ "\ufffe\uffff\u0000", [
                span(0, 53), span(53, 53), span(9, 10), none, none, none, none, none, none, none
    ]);
    // A zero digit whose run reaches a surrogate has no UTF-8 form.
    const highZero = symbols(cast(wchar) 0xD7F8, ',', '.', '-', '%', '\u2030', "E");
    assert(!bodySymbolsEncodable(highZero));
    const lowMinus = symbols('0', ',', '.', cast(wchar) 0xDC00, '%', '\u2030', "E");
    assert(!bodySymbolsEncodable(lowMinus));
}

// The pattern's minus, percent and per-mille tokens and the implicit negative prefix expand to the symbols.
unittest
{
    const arabic = symbols('\u0660', '\u066c', '\u066b', '\u2212', '\u066a', '\u0609', "\u0623\u0633");
    expectLong("0%", arabic, 100, -25, "\u2212\u0662\u0665\u0660\u0660\u066a", [
        span(3, 11), span(11, 11), none, none, none, none, none, span(0, 3), span(11, 13), none
    ]);

    const ascii = symbols('A', '_', ':', '~', 'P', 'M', "e");
    expectLong("'%'0\u2030", ascii, 1000, -1, "~%BAAAM", [
        span(2, 6), span(6, 6), none, none, none, none, none, span(0, 1), none, span(6, 7)
    ]);
}

// BigDecimal shares the exponent renderer: three-byte digits, a two-byte multiplication sign in the separator.
unittest
{
    const data = symbols('\u0966', '\u00a0', ',', '-', '%', '\u2030', "\u00d710^");
    const pattern = compiled("0.###E0", data);
    char[16] digits;
    char[64] output;
    DecimalBigStatus status;
    DecimalFieldSpans fields;
    const required = renderBigDecimal("0.00098765", true, pattern, data, digits[], output[],
            FixedRoundingMode.halfEven, status, &fields);
    assert(status == DecimalBigStatus.complete);
    assert(output[0 .. required] == "-\u096f,\u096e\u096d\u096c\u00d710^-\u096a");
    assert(fields.spans[] == [
        span(1, 4), span(5, 14), none, span(4, 5), span(14, 19), span(19, 20), span(20, 23),
        span(0, 1), none, none
    ]);
}
