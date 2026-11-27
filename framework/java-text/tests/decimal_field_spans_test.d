module flint.java.text.internal.decimal_field_spans_test;

import flint.java.text.internal.decimalexponent : renderExponentLong;
import flint.java.text.internal.decimalfixed : DecimalField, DecimalFieldSpan, DecimalFieldSpans,
    DecimalFixedPattern, renderDecimalLong;
import flint.java.text.internal.decimalfixedbinary : tryRenderDecimalDouble;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

// Expected spans are pinned Temurin 21.0.13+9 FieldPosition results with ROOT symbols, as UTF-8 byte offsets.
private DecimalFixedPattern compiled(string text)
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
    return pattern;
}

private enum DecimalFieldSpan none = DecimalFieldSpan.init;

private DecimalFieldSpan span(size_t begin, size_t end)
{
    return DecimalFieldSpan(begin, end, true);
}

private string renderDouble(string text, int multiplier, ulong bits, ref DecimalFieldSpans spans,
        return ref char[64] output)
{
    const pattern = compiled(text);
    DecimalSymbolData symbols;
    size_t required;
    FixedRoundingStatus status;
    assert(tryRenderDecimalDouble(bits, multiplier, pattern, symbols, output[], required,
            FixedRoundingMode.halfEven, status, &spans));
    assert(status == FixedRoundingStatus.complete);
    return output[0 .. required].idup;
}

@("Fixed spans cover grouped integers, the decimal separator and the fraction")
unittest
{
    char[64] output;
    DecimalFieldSpans spans;
    assert(renderDouble("#,##0.###", 1, 0x4132_d687_4000_0000, spans, output) == "1,234,567.25");
    assert(spans.spans[DecimalField.integer] == span(0, 9));
    assert(spans.spans[DecimalField.groupingSeparator] == span(1, 2));
    assert(spans.spans[DecimalField.decimalSeparator] == span(9, 10));
    assert(spans.spans[DecimalField.fraction] == span(10, 12));
    assert(spans.spans[DecimalField.exponent] == none);

    // 0. always shows the separator, so the empty fraction starts after it.
    DecimalFieldSpans shown;
    assert(renderDouble("0.", 1, 0x40c8_1c80_0000_0000, shown, output) == "12345.");
    assert(shown.spans[DecimalField.integer] == span(0, 5));
    assert(shown.spans[DecimalField.decimalSeparator] == span(5, 6));
    assert(shown.spans[DecimalField.fraction] == span(6, 6));
}

@("Reporting fields bypasses the grouped fast path like Java's FieldPosition overload")
unittest
{
    char[64] output;
    DecimalFieldSpans spans;
    // -0.0005: format(double) uses the fast path and prints -0.001; a caller FieldPosition gives -0.
    assert(renderDouble("#,##0.###", 1, 0xbf40_624d_d2f1_a9fc, spans, output) == "-0");
    assert(spans.spans[DecimalField.integer] == span(1, 2));
    assert(spans.spans[DecimalField.fraction] == span(2, 2));
    assert(spans.spans[DecimalField.decimalSeparator] == none);
    assert(spans.spans[DecimalField.groupingSeparator] == none);

    const pattern = compiled("#,##0.###");
    DecimalSymbolData symbols;
    size_t required;
    assert(tryRenderDecimalDouble(0xbf40_624d_d2f1_a9fc, pattern, symbols, output[], required));
    assert(output[0 .. required] == "-0.001");
}

@("Exponent spans split the mantissa and report the exponent sign and padded digits")
unittest
{
    char[64] output;
    DecimalFieldSpans spans;
    assert(renderDouble("0.00E00", 1, 0x3f20_2e4b_6ce5_dc68, spans, output) == "1.23E-04");
    assert(spans.spans[DecimalField.integer] == span(0, 1));
    assert(spans.spans[DecimalField.decimalSeparator] == span(1, 2));
    assert(spans.spans[DecimalField.fraction] == span(2, 4));
    assert(spans.spans[DecimalField.exponentSymbol] == span(4, 5));
    assert(spans.spans[DecimalField.exponentSign] == span(5, 6));
    assert(spans.spans[DecimalField.exponent] == span(6, 8));
    assert(spans.spans[DecimalField.groupingSeparator] == none);
}

@("Long spans follow the affixes of the chosen subpattern")
unittest
{
    DecimalSymbolData symbols;
    char[64] output;
    DecimalFieldSpans grouped;
    const fixed = compiled("#,##0.###");
    const fixedSize = renderDecimalLong(-1_234_567, 1, fixed, symbols, output[], &grouped);
    assert(output[0 .. fixedSize] == "-1,234,567");
    assert(grouped.spans[DecimalField.integer] == span(1, 10));
    assert(grouped.spans[DecimalField.groupingSeparator] == span(2, 3));
    assert(grouped.spans[DecimalField.fraction] == span(10, 10));

    DecimalFieldSpans exponent;
    FixedRoundingStatus status;
    const scientific = compiled("0.0E0;(0.0E0)");
    const size = renderExponentLong(-1, 1, scientific, symbols, output[],
            FixedRoundingMode.halfEven, status, &exponent);
    assert(output[0 .. size] == "(1.0E0)");
    assert(exponent.spans[DecimalField.integer] == span(1, 2));
    assert(exponent.spans[DecimalField.decimalSeparator] == span(2, 3));
    assert(exponent.spans[DecimalField.fraction] == span(3, 4));
    assert(exponent.spans[DecimalField.exponentSymbol] == span(4, 5));
    assert(exponent.spans[DecimalField.exponentSign] == none);
    assert(exponent.spans[DecimalField.exponent] == span(5, 6));
}

@("NaN and infinity report the symbol as the integer field")
unittest
{
    char[64] output;
    DecimalFieldSpans infinity;
    assert(renderDouble("0%", 100, 0xfff0_0000_0000_0000, infinity, output) == "-∞%");
    assert(infinity.spans[DecimalField.integer] == span(1, 1 + "∞".length));
    assert(infinity.spans[DecimalField.fraction] == none);

    DecimalFieldSpans nan;
    assert(renderDouble("0%", 100, 0x7ff8_0000_0000_0000, nan, output) == "NaN");
    assert(nan.spans[DecimalField.integer] == span(0, 3));
}

@("A short buffer leaves the spans untouched")
unittest
{
    const pattern = compiled("#,##0.###");
    DecimalSymbolData symbols;
    char[4] output = '*';
    DecimalFieldSpans spans;
    size_t required;
    FixedRoundingStatus status;
    assert(tryRenderDecimalDouble(0x4132_d687_4000_0000, 1, pattern, symbols, output[], required,
            FixedRoundingMode.halfEven, status, &spans));
    assert(required == "1,234,567.25".length);
    assert(output == "****");
    assert(spans == DecimalFieldSpans.init);
}

@("Recording keeps the first nonempty span and replaces an empty one")
unittest
{
    DecimalFieldSpans spans;
    spans.record(DecimalField.integer, 4, 4);
    spans.record(DecimalField.integer, 1, 3);
    assert(spans.spans[DecimalField.integer] == span(1, 3));
    spans.record(DecimalField.integer, 5, 7);
    assert(spans.spans[DecimalField.integer] == span(1, 3));
}
