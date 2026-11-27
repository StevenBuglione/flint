module flint.java.text.internal.decimal_affix_fields_test;

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

private string renderLong(string text, long value, ref DecimalFieldSpans spans, return ref char[64] output)
{
    const pattern = compiled(text);
    DecimalSymbolData symbols;
    return output[0 .. renderDecimalLong(value, 1, pattern, symbols, output[], &spans)].idup;
}

@("Percent and per-mille tokens report their UTF-8 spans in either affix")
unittest
{
    char[64] output;
    DecimalFieldSpans prefix;
    // ‰ is three UTF-8 bytes and one UTF-16 unit; Java reports 0:1.
    assert(renderDouble("‰0.0;-0.0", 1000, 0x4004_0000_0000_0000, prefix, output) == "‰2500.0");
    assert(prefix.spans[DecimalField.perMille] == span(0, 3));
    assert(prefix.spans[DecimalField.integer] == span(3, 7));
    assert(prefix.spans[DecimalField.sign] == none);

    // The explicit negative subpattern has no per-mille token, only its minus sign.
    DecimalFieldSpans negative;
    assert(renderDouble("‰0.0;-0.0", 1000, 0xc004_0000_0000_0000, negative, output) == "-2500.0");
    assert(negative.spans[DecimalField.sign] == span(0, 1));
    assert(negative.spans[DecimalField.perMille] == none);

    DecimalFieldSpans suffix;
    assert(renderDouble("0.#‰", 1000, 0xc004_0000_0000_0000, suffix, output) == "-2500‰");
    assert(suffix.spans[DecimalField.sign] == span(0, 1));
    assert(suffix.spans[DecimalField.perMille] == span(5, 8));

    // A percent token only in the negative subpattern is reported without scaling the value.
    DecimalFieldSpans negativeOnly;
    assert(renderLong("0;0%", -15, negativeOnly, output) == "15%");
    assert(negativeOnly.spans[DecimalField.percent] == span(2, 3));
    assert(negativeOnly.spans[DecimalField.sign] == none);
}

@("The implicit negative prefix is a symbolic sign ahead of the positive prefix tokens")
unittest
{
    char[64] output;
    DecimalFieldSpans spans;
    assert(renderDouble("%0", 100, 0xbff0_0000_0000_0000, spans, output) == "-%100");
    assert(spans.spans[DecimalField.sign] == span(0, 1));
    assert(spans.spans[DecimalField.percent] == span(1, 2));
    assert(spans.spans[DecimalField.integer] == span(2, 5));

    // An uncompiled pattern keeps the same symbolic default.
    DecimalFixedPattern pattern;
    DecimalSymbolData symbols;
    DecimalFieldSpans initial;
    assert(output[0 .. renderDecimalLong(-5, 1, pattern, symbols, output[], &initial)] == "-5");
    assert(initial.spans[DecimalField.sign] == span(0, 1));

    // A quoted minus is literal text, so only the implicit sign is reported.
    DecimalFieldSpans quoted;
    assert(renderDouble("'-'0.0", 1, 0xbff0_0000_0000_0000, quoted, output) == "--1.0");
    assert(quoted.spans[DecimalField.sign] == span(0, 1));
    DecimalFieldSpans positive;
    assert(renderDouble("'-'0.0", 1, 0x3ff0_0000_0000_0000, positive, output) == "-1.0");
    assert(positive.spans[DecimalField.sign] == none);
}

@("The first nonempty sign wins, so a prefix sign hides a suffix sign")
unittest
{
    char[64] output;
    DecimalFieldSpans both;
    assert(renderLong("-0-", -1, both, output) == "--1-");
    assert(both.spans[DecimalField.sign] == span(0, 1));

    DecimalFieldSpans suffix;
    assert(renderLong("0;0-", -25, suffix, output) == "25-");
    assert(suffix.spans[DecimalField.sign] == span(2, 3));

    // The exponent renderer reports affix signs separately from the exponent sign.
    const pattern = compiled("0E0-");
    DecimalSymbolData symbols;
    FixedRoundingStatus status;
    DecimalFieldSpans exponent;
    const required = renderExponentLong(-25, 1, pattern, symbols, output[],
            FixedRoundingMode.halfEven, status, &exponent);
    assert(output[0 .. required] == "-2E1-");
    assert(exponent.spans[DecimalField.sign] == span(0, 1));
    assert(exponent.spans[DecimalField.exponentSign] == none);
}

@("Infinity reports the affix sign around the token, and NaN has no affixes")
unittest
{
    char[64] output;
    DecimalFieldSpans infinity;
    // ∞ is three UTF-8 bytes; Java reports the suffix minus at 3:4 in UTF-16.
    assert(renderDouble("-0.0E0;(0.0E0)-", 1, 0xfff0_0000_0000_0000, infinity, output) == "(∞)-");
    assert(infinity.spans[DecimalField.integer] == span(1, 4));
    assert(infinity.spans[DecimalField.sign] == span(5, 6));

    DecimalFieldSpans nan;
    assert(renderDouble("-0.0E0;(0.0E0)-", 0, 0xfff0_0000_0000_0000, nan, output) == "NaN");
    assert(nan.spans[DecimalField.sign] == none);
}
