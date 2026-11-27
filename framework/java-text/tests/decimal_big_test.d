module flint.java.text.internal.decimal_big_test;

import flint.java.text.internal.decimalbig : DecimalBigStatus, renderBigDecimal, renderBigInteger;
import flint.java.text.internal.decimalfixed : DecimalField, DecimalFieldSpan, DecimalFieldSpans, DecimalFixedPattern;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

// Expected text is pinned Temurin 21.0.13+9 DecimalFormat output with ROOT symbols. The input text is
// BigDecimal.toString() or BigInteger.toString() of the magnitude, as DecimalFormat's DigitList reads it.
private DecimalFixedPattern compiled(string text)
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
    return pattern;
}

private DecimalFixedPattern widths(string text, int minInt, int maxInt, int minFrac, int maxFrac)
{
    auto pattern = compiled(text);
    pattern.setMinimumIntegerDigits(minInt);
    pattern.setMaximumIntegerDigits(maxInt);
    pattern.setMinimumFractionDigits(minFrac);
    pattern.setMaximumFractionDigits(maxFrac);
    return pattern;
}

private string decimal(const DecimalFixedPattern pattern, string text, bool negative = false,
        FixedRoundingMode mode = FixedRoundingMode.halfEven)
{
    DecimalSymbolData symbols;
    auto digits = new char[text.length];
    auto output = new char[1_024];
    DecimalBigStatus status;
    const required = renderBigDecimal(text, negative, pattern, symbols, digits, output, mode, status);
    if (status != DecimalBigStatus.complete)
        return status == DecimalBigStatus.inexact ? "inexact" : "range";
    return output[0 .. required].idup;
}

private string integer(const DecimalFixedPattern pattern, string text, bool negative = false)
{
    DecimalSymbolData symbols;
    auto digits = new char[text.length];
    auto output = new char[1_024];
    DecimalBigStatus status;
    const required = renderBigInteger(text, negative, pattern, symbols, digits, output,
            FixedRoundingMode.halfEven, status);
    assert(status == DecimalBigStatus.complete);
    return output[0 .. required].idup;
}

private string repeat(char c, size_t count)
{
    auto text = new char[count];
    text[] = c;
    return text.idup;
}

@("A BigDecimal rounds exactly and keeps the sign of a value that rounds to zero")
unittest
{
    // Binary64 2.675 is below the tie and formats as 2.67; the exact decimal is a tie and rounds to even 8.
    assert(decimal(compiled("0.00"), "2.675") == "2.68");
    assert(decimal(compiled("0.00"), "2.675", false, FixedRoundingMode.unnecessary) == "inexact");
    assert(decimal(compiled("0.00"), "0.0005", true) == "-0.00");
    assert(decimal(compiled("0E0"), "0.0005", true) == "-5E-4");
    assert(decimal(compiled("#,##0.###"),
            "123456789012345678901234567890.123456789") == "123,456,789,012,345,678,901,234,567,890.123");
    // DigitList reads the scientific form BigDecimal.toString() uses for small and negative-scale values.
    assert(decimal(compiled("0.###E0"), "1.23E-7") == "1.23E-7");
    assert(decimal(compiled("0"), "1.00E+4") == "10000");
}

@("Arbitrary-precision formatting uses DecimalFormat's own widths beyond the primitive caps")
unittest
{
    const twos = repeat('2', 37);
    // Primitive values cap integer digits at 309; a BigInteger keeps all 350.
    assert(integer(widths("0", 350, 360, 0, 0), twos) == repeat('0', 313) ~ twos);
    // Primitive values cap fraction digits at 340; a BigDecimal keeps all 345.
    assert(decimal(widths("0.00", 1, 310, 345, 350), "12.5") == "12.5" ~ repeat('0', 344));
    assert(decimal(widths("0E0", 1, 1, 0, int.max),
            "0.3333333333333333333333333333333333") == "3.333333333333333333333333333333333E-1");
}

@("Exponential digit limits differ between BigDecimal and BigInteger at zero")
unittest
{
    const none = widths("0E0", 0, 0, 0, 0);
    // A BigDecimal rounds to zero total digits: 15 is a tie that HALF_EVEN drops and UP carries.
    assert(decimal(none, "15") == "E0");
    assert(decimal(none, "15", false, FixedRoundingMode.up) == ".1E3");
    // DigitList.set(BigInteger) ignores a total digit limit that is not positive.
    const twos = repeat('2', 37);
    assert(integer(none, twos) == "." ~ twos ~ "E37");
}

@("Decimal positions where Java's int arithmetic wraps are declined")
unittest
{
    // The decimal position 2^31 itself does not fit an int.
    assert(decimal(compiled("0E0"), "1E+2147483647") == "range");
    // Rounding 9.9E+2147483646 to one digit carries the position past Integer.MAX_VALUE.
    assert(decimal(compiled("0E0"), "9.9E+2147483646") == "range");
    assert(decimal(compiled("0E0"), "9.9E+2147483645") == "1E2147483646");
    // An engineering repeat of three subtracts three from the position Integer.MIN_VALUE + 2.
    assert(decimal(compiled("0E0"), "1E-2147483647") == "1E-2147483647");
    assert(decimal(compiled("##0.##E0"), "1E-2147483647") == "range");
    assert(decimal(compiled("0.###"), "1E-2147483647") == "0");
}

@("Body and affix fields are reported and a short buffer stays untouched")
unittest
{
    DecimalSymbolData symbols;
    const pattern = compiled("#,##0.00;(#,##0.00)");
    enum text = "1234567.891";
    char[text.length] digits;
    char[8] tooShort = '*';
    DecimalBigStatus status;
    assert(renderBigDecimal(text, true, pattern, symbols, digits, tooShort,
            FixedRoundingMode.halfEven, status) == "(1,234,567.89)".length);
    assert(tooShort[] == "********");

    char[32] output;
    DecimalFieldSpans spans;
    const required = renderBigDecimal(text, true, pattern, symbols, digits, output,
            FixedRoundingMode.halfEven, status, &spans);
    assert(output[0 .. required] == "(1,234,567.89)");
    assert(spans.spans[DecimalField.integer] == DecimalFieldSpan(1, 10, true));
    assert(spans.spans[DecimalField.groupingSeparator] == DecimalFieldSpan(2, 3, true));
    assert(spans.spans[DecimalField.fraction] == DecimalFieldSpan(11, 13, true));
}
