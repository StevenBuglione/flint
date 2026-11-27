module flint.java.text.internal.decimal_exponent_test;

import flint.java.text.internal.decimalexponent : renderExponentLong;
import flint.java.text.internal.decimalfixed : DecimalFixedPattern;
import flint.java.text.internal.decimalfixedbinary : tryRenderDecimalDouble;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

// Expected outputs are pinned Temurin 21.0.13+9 DecimalFormat results with ROOT symbols.
private struct LongRow
{
    string pattern;
    int multiplier;
    FixedRoundingMode mode;
    long value;
    string expected;
}

private struct DoubleRow
{
    string pattern;
    int multiplier;
    FixedRoundingMode mode;
    ulong bits;
    string expected;
}

private DecimalFixedPattern compiled(string text)
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
    assert(pattern.minimumExponentDigits != 0);
    return pattern;
}

@("Exponent patterns format longs with engineering repeats and significant rounding")
unittest
{
    alias M = FixedRoundingMode;
    foreach (row; [
        LongRow("##0.#####E0", 1, M.halfEven, 1_234_567, "1.234567E6"),
        LongRow("0.00E00", 1, M.halfEven, long.min, "-9.22E18"),
        LongRow("000E000", 1, M.halfEven, 0, "000E000"),
        LongRow("0.0E0;(0.0E0)", -2, M.halfUp, 25, "(5.0E1)"),
        LongRow("0E0", 1, M.halfEven, 25, "2E1"), LongRow("0E0", 1, M.halfEven, 15, "2E1"),
    ])
    {
        const pattern = compiled(row.pattern);
        DecimalSymbolData symbols;
        char[32] output;
        output[] = 'x';
        FixedRoundingStatus status;
        const required = renderExponentLong(row.value, row.multiplier, pattern, symbols,
                output[0 .. 1], row.mode, status);
        assert(status == FixedRoundingStatus.complete && required == row.expected.length && output[0] == 'x');
        assert(renderExponentLong(row.value, row.multiplier, pattern, symbols, output[], row.mode,
                status) == row.expected.length);
        assert(output[0 .. row.expected.length] == row.expected && output[row.expected.length] == 'x');
    }
}

@("An inexact UNNECESSARY exponent long reports the rounding failure and writes nothing")
unittest
{
    const pattern = compiled("0.00E00");
    DecimalSymbolData symbols;
    char[32] output;
    output[] = 'x';
    FixedRoundingStatus status;
    assert(renderExponentLong(1_234_567, 1, pattern, symbols, output[], FixedRoundingMode.unnecessary, status) == 0);
    assert(status == FixedRoundingStatus.inexact && output[0] == 'x');
}

@("Exponent patterns format binary64 values, signed zero, subnormals and specials")
unittest
{
    alias M = FixedRoundingMode;
    foreach (row; [
        DoubleRow("##0.#####E0", 1, M.halfEven, 0x3f20_2e4b_6ce5_dc68, "123.45E-6"),
        DoubleRow("0.00E00", 1, M.halfEven, 0x4005_6666_6666_6666, "2.67E00"),
        DoubleRow(".##E0", 1, M.halfEven, 1, ".49E-323"),
        DoubleRow("0E0%", 100, M.halfEven, 0x3ff8_0000_0000_0000, "2E2%"),
        DoubleRow("0.E0", 1, M.halfEven, 0x8000_0000_0000_0000, "-0.E0"),
        DoubleRow("#,##0.0E0", 1, M.ceiling, 0x7fef_ffff_ffff_ffff, "1.7977E308"),
        DoubleRow("0.00E00", 1, M.unnecessary, 0x3fb9_9999_9999_999a, "1.00E-01"),
        DoubleRow("0.00E00", 1, M.halfEven, 0xfff0_0000_0000_0000, "-∞"),
    ])
    {
        const pattern = compiled(row.pattern);
        DecimalSymbolData symbols;
        char[32] output;
        output[] = 'x';
        size_t required;
        FixedRoundingStatus status;
        assert(tryRenderDecimalDouble(row.bits, row.multiplier, pattern, symbols, output[0 .. 1],
                required, row.mode, status));
        assert(status == FixedRoundingStatus.complete && required == row.expected.length && output[0] == 'x');
        assert(tryRenderDecimalDouble(row.bits, row.multiplier, pattern, symbols, output[],
                required, row.mode, status));
        assert(output[0 .. required] == row.expected && output[required] == 'x');
    }
}

@("Zero total exponent digits round binary64 to an empty digit list")
unittest
{
    auto pattern = compiled("0.###E0");
    pattern.setMinimumIntegerDigits(0);
    pattern.setMaximumIntegerDigits(0);
    pattern.setMaximumFractionDigits(0);
    DecimalSymbolData symbols;
    char[8] output;
    size_t required;
    FixedRoundingStatus status;
    // 999.9999 rounds DOWN to no digits, then formats as zero without integer digits.
    assert(tryRenderDecimalDouble(0x408f_3fff_cb92_3a2a, 1, pattern, symbols, output[], required,
            FixedRoundingMode.down, status));
    assert(output[0 .. required] == "E0");
}
