module flint.java.text.internal.decimal_parse_big_test;

import flint.java.text.internal.decimaldigitlist : FixedRoundingMode;
import flint.java.text.internal.decimalfixed : DecimalFixedPattern;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalparse : DecimalParseKind, DecimalParseOptions,
    DecimalParseResult, parseDecimal;
import flint.java.text.internal.decimalparsebig : DecimalBigParseStatus, DecimalBigParseValue, parseBigDecimalValue;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

private struct Parsed
{
    DecimalBigParseStatus status;
    DecimalBigParseValue value;
    char[64] output;

    const(char)[] unscaled() const return
    {
        return output[0 .. value.length];
    }
}

private Parsed parseBig(scope const(char)[] text, int multiplier,
        FixedRoundingMode mode = FixedRoundingMode.halfEven, size_t capacity = 64)
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern("0.###E0", pattern) == DecimalCompileStatus.accepted);
    DecimalSymbolData symbols;
    DecimalParseOptions options;
    options.multiplier = multiplier;
    options.parseBigDecimal = true;
    char[64] digits;
    const result = parseDecimal(text, 0, pattern, symbols, options, digits[]);
    assert(result.kind == DecimalParseKind.bigDecimal && result.index == text.length);
    Parsed parsed;
    parsed.status = parseBigDecimalValue(result, digits[], multiplier, mode,
            parsed.output[0 .. capacity], parsed.value);
    return parsed;
}

private void expect(scope const Parsed parsed, bool negative, string unscaled, size_t zeros, int scale)
{
    assert(parsed.status == DecimalBigParseStatus.complete);
    assert(parsed.value.negative == negative && parsed.unscaled == unscaled);
    assert(parsed.value.zeros == zeros && parsed.value.scale == scale);
}

// Infinity and a zero multiplier answer a Double even when isParseBigDecimal is set.
unittest
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern("0", pattern) == DecimalCompileStatus.accepted);
    DecimalSymbolData symbols;
    DecimalParseOptions options;
    options.parseBigDecimal = true;
    char[8] digits;
    assert(parseDecimal("∞", 0, pattern, symbols, options, digits[]).kind == DecimalParseKind.doubleValue);
    options.multiplier = 0;
    const zero = parseDecimal("5", 0, pattern, symbols, options, digits[]);
    assert(zero.kind == DecimalParseKind.doubleValue && zero.doubleValue == double.infinity);
    options.multiplier = 1;
    assert(parseDecimal("5", 0, pattern, symbols, options, digits[]).kind == DecimalParseKind.bigDecimal);
}

// DigitList.getBigDecimal keeps parsed trailing zeros, which stay implicit after the stored digits.
unittest
{
    expect(parseBig("1.500", 1), false, "15", 2, 3);
    expect(parseBig("-0.000", 1), false, "", 0, 3);
    expect(parseBig("0E5", 1), false, "", 0, -5);
    expect(parseBig("-12E3", 1), true, "12", 0, -3);
    // Only the stored digits need room.
    expect(parseBig("1000000", 1, FixedRoundingMode.halfEven, 1), false, "1", 6, 0);
    assert(parseBig("12", 1, FixedRoundingMode.halfEven, 1).status == DecimalBigParseStatus.capacity);
}

// Exact quotients take the smallest scale at or above the dividend's, and zeros after an exhausted remainder stay
// implicit.
unittest
{
    expect(parseBig("1", 1024), false, "9765625", 0, 10);
    expect(parseBig("1.0", 4), false, "25", 0, 2);
    expect(parseBig("1.5E-2147483648", 1), false, "15", 0, -int.max);
    expect(parseBig("100", 4), false, "25", 0, 0);
    expect(parseBig("1000000", 2), false, "5", 5, 0);
    expect(parseBig("10", int.min), true, "4656612873077392578125", 0, 30);
    expect(parseBig("-6", -3), false, "2", 0, 0);
    assert(parseBig("1000000", 3, FixedRoundingMode.halfEven, 5).status == DecimalBigParseStatus.capacity);
}

// A quotient that does not terminate rounds at the dividend's scale with the quotient's sign, before negation.
unittest
{
    expect(parseBig("7", 3), false, "2", 0, 0);
    expect(parseBig("-7", 3, FixedRoundingMode.floor), true, "2", 0, 0);
    expect(parseBig("7", -3, FixedRoundingMode.floor), true, "3", 0, 0);
    expect(parseBig("7", 3, FixedRoundingMode.ceiling), false, "3", 0, 0);
    expect(parseBig("7", -3, FixedRoundingMode.ceiling), true, "2", 0, 0);
    // BigDecimal has no negative zero.
    expect(parseBig("-1", 3, FixedRoundingMode.down), false, "", 0, 0);
    expect(parseBig("1", 3, FixedRoundingMode.up), false, "1", 0, 0);
    expect(parseBig("1", 3, FixedRoundingMode.down), false, "", 0, 0);
    // The carry lengthens the quotient: 299 / 3 rounds 99.67 up to 100.
    expect(parseBig("299", 3), false, "100", 0, 0);
    assert(parseBig("299", 3, FixedRoundingMode.halfEven, 2).status == DecimalBigParseStatus.capacity);
    assert(parseBig("7", 3, FixedRoundingMode.unnecessary).status == DecimalBigParseStatus.inexact);
}

// Ties only reach the rounding path when the exact quotient's scale would overflow. Half modes compare twice the
// remainder with the divisor; a tie looks at the last quotient digit.
unittest
{
    expect(parseBig("5", 10), false, "5", 0, 1);
    expect(parseBig("1.5E-2147483646", 2), false, "8", 0, int.max);
    expect(parseBig("2.5E-2147483646", 2), false, "12", 0, int.max);
    expect(parseBig("2.5E-2147483646", 2, FixedRoundingMode.halfUp), false, "13", 0, int.max);
    expect(parseBig("2.5E-2147483646", 2, FixedRoundingMode.halfDown), false, "12", 0, int.max);
}

// divide(BigDecimal, MathContext) overflows its working scale near Integer.MAX_VALUE and parse rounds instead. For
// a one-digit divisor the working scale adds 1 + 4, less one when the dividend's leading digit is larger.
unittest
{
    expect(parseBig("1E-2147483642", 2), false, "5", 0, int.max - 4);
    expect(parseBig("1E-2147483643", 2), false, "", 0, int.max - 4);
    expect(parseBig("1E-2147483643", 2, FixedRoundingMode.up), false, "1", 0, int.max - 4);
    expect(parseBig("3E-2147483643", 2, FixedRoundingMode.up), false, "15", 0, int.max - 3);
    expect(parseBig("3E-2147483644", 2, FixedRoundingMode.up), false, "2", 0, int.max - 3);
    // A quotient that is exact at the dividend's scale needs no rounding, even under UNNECESSARY or UP.
    expect(parseBig("2E-2147483644", 2, FixedRoundingMode.unnecessary), false, "1", 0, int.max - 3);
    expect(parseBig("2E-2147483646", 2, FixedRoundingMode.up), false, "1", 0, int.max - 1);
}

// Scales beyond the int range: Java throws ArithmeticException, or NumberFormatException for a zero.
unittest
{
    assert(parseBig("1E-2147483648", 1).status == DecimalBigParseStatus.scaleRange);
    assert(parseBig("0E-2147483648", 2).status == DecimalBigParseStatus.scaleRange);
    expect(parseBig("0E-2147483647", 2), false, "", 0, int.max);
}
