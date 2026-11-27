module flint.java.text.internal.decimal_parse_test;

import flint.java.text.internal.decimalfixed : DecimalFixedPattern;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalparse : DecimalParseKind, DecimalParseOptions,
    DecimalParseResult, parseDecimal;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

private DecimalParseResult parse(string patternText, scope const(char)[] text, size_t start = 0,
        DecimalParseOptions options = DecimalParseOptions.init, size_t capacity = 64)
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern(patternText, pattern) == DecimalCompileStatus.accepted);
    DecimalSymbolData symbols;
    char[64] digits;
    return parseDecimal(text, start, pattern, symbols, options, digits[0 .. capacity]);
}

private void expectLong(DecimalParseResult result, long value, size_t index)
{
    assert(result.kind == DecimalParseKind.longValue && result.longValue == value);
    assert(result.index == index && result.errorIndex == -1);
}

private void expectFailure(DecimalParseResult result, size_t index, ptrdiff_t errorIndex)
{
    assert(result.kind == DecimalParseKind.failed && result.index == index && result.errorIndex == errorIndex);
}

@("DecimalFormat.parse reads grouped Java digits and stops where Java stops")
unittest
{
    expectLong(parse("#,##0.###", "-1,234"), -1234, 6);
    // A trailing grouping separator is not consumed.
    expectLong(parse("#,##0.###", "1,234,"), 1234, 5);
    DecimalParseOptions ungrouped;
    ungrouped.groupingUsed = false;
    expectLong(parse("#,##0.###", "1,234", 0, ungrouped), 1, 1);
    expectLong(parse("0", "00012"), 12, 5);
    // Arabic-Indic digits count, a supplementary digit does not.
    expectLong(parse("0", "١٢٣"), 123, 6);
    expectLong(parse("0", "1\U0001D7CF"), 1, 1);
    // UTF-8 offsets follow a non-zero start.
    expectLong(parse("0", "x\U0001F600-7", 5), -7, 7);
    // A leading grouping separator is skipped once a digit follows it.
    expectLong(parse("0", ",1"), 1, 2);
    expectFailure(parse("0", ",1", 0, ungrouped), 0, 0);
    expectFailure(parse("#,##0.00;(#,##0.00)", "(5"), 0, 2);
}

@("DecimalFormat.parse keeps the Java signs, extremes and longest affixes")
unittest
{
    expectLong(parse("0", "-9223372036854775808"), long.min, 20);
    auto overflow = parse("0", "9223372036854775808");
    assert(overflow.kind == DecimalParseKind.decimalDigits && overflow.decimalAt == 19 && overflow.positive);
    auto negativeZero = parse("0", "-0.000");
    assert(negativeZero.kind == DecimalParseKind.decimalDigits && !negativeZero.positive && negativeZero.count == 0);
    DecimalParseOptions integerOnly;
    integerOnly.integerOnly = true;
    expectLong(parse("0", "-0.000", 0, integerOnly), 0, 2);
    expectLong(parse("'a'0;'ab'0", "ab5"), -5, 3);
    expectLong(parse("0'x';0'xy'", "5xy"), -5, 3);
    expectFailure(parse("0-;0'-'", "5-"), 0, 1);
}

@("DecimalFormat.parse narrows exponents as Java does")
unittest
{
    expectLong(parse("0", "-1E3"), -1000, 4);
    expectLong(parse("0", "1E3E4"), 1000, 3);
    expectLong(parse("0", "1E9223372036854775808"), 1, 1);
    expectLong(parse("0", "1E-9223372036854775808"), 1, 22);
    // The exponent wraps decimalAt to int.min, which Java then converts to 0.0.
    auto wrapped = parse("0", "1E2147483647");
    assert(wrapped.kind == DecimalParseKind.decimalDigits && wrapped.decimalAt == int.min && wrapped.index == 12);
    auto fraction = parse("0", "1E9223372036854775807");
    assert(fraction.kind == DecimalParseKind.decimalDigits && fraction.decimalAt == 0);
}

@("DecimalFormat.parse applies Java multipliers, NaN and infinity")
unittest
{
    DecimalParseOptions percent;
    percent.multiplier = 100;
    auto share = parse("0%", "5%", 0, percent);
    assert(share.kind == DecimalParseKind.doubleValue && share.doubleValue == 0.05 && share.index == 2);
    expectLong(parse("0%", "500%", 0, percent), 5, 4);
    DecimalParseOptions negated;
    negated.multiplier = -2;
    // Long.MIN_VALUE is not negated again after division, as in Java.
    expectLong(parse("0", "-9223372036854775808", 0, negated), 4_611_686_018_427_387_904, 20);
    DecimalParseOptions minusOne;
    minusOne.multiplier = -1;
    expectLong(parse("0", "-9223372036854775808", 0, minusOne), long.min, 20);
    DecimalParseOptions zero;
    zero.multiplier = 0;
    assert(parse("0", "0", 0, zero).doubleValue != parse("0", "0", 0, zero).doubleValue);
    assert(parse("0", "-3", 0, zero).doubleValue == -double.infinity);
    assert(parse("0", "-∞", 0, negated).doubleValue == double.infinity);
    auto nan = parse("0", "NaNx");
    assert(nan.kind == DecimalParseKind.doubleValue && nan.doubleValue != nan.doubleValue && nan.index == 3);
}

@("DecimalFormat.parse keeps trailing zeros implicit and reports a short digit buffer")
unittest
{
    auto padded = parse("0", "9223372036854775807.000000000000000000000000000000", 0, DecimalParseOptions.init, 19);
    assert(padded.kind == DecimalParseKind.longValue && padded.longValue == long.max);
    assert(padded.count == 49 && padded.stored == 19);
    auto tooLong = parse("0", "12345", 0, DecimalParseOptions.init, 4);
    assert(tooLong.kind == DecimalParseKind.capacity && tooLong.count == 5 && tooLong.index == 5);
}
