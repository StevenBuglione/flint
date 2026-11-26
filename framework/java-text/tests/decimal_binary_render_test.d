module flint.java.text.internal.decimal_binary_render_test;

import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalfixed : DecimalFixedPattern, tryRenderDecimalDouble;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

@("The fixed-point binary renderer preserves Java decimal digits and signed affixes")
unittest
{
    static void check(string patternText, ulong bits, string expected)
    {
        DecimalFixedPattern pattern;
        assert(compileFixedDecimalPattern(patternText, pattern) == DecimalCompileStatus.accepted);
        DecimalSymbolData symbols;
        char[48] output;
        output[] = 'x';
        size_t required;
        assert(expected.length > 1);
        assert(tryRenderDecimalDouble(bits, pattern, symbols, output[0 .. 1], required));
        assert(required == expected.length && output[0] == 'x');
        assert(tryRenderDecimalDouble(bits, pattern, symbols, output[], required));
        assert(output[0 .. required] == expected && output[required] == 'x');
    }

    check("0.00", 0x8000_0000_0000_0000, "-0.00");
    check("0.00", 0x4005_6666_6666_6666, "2.67");
    check("0.###", 0xbf40_624d_d2f1_a9fc, "-0");
    check("0.00;(0.00)", 0xc005_6666_6666_6666, "(2.67)");
    check("0", 0x44b5_2d02_c7e1_4af6, "99999999999999990000000");
}

@("The general binary renderer leaves its unsupported profiles untouched")
unittest
{
    DecimalFixedPattern pattern;
    DecimalSymbolData symbols;
    char[24] output;
    output[] = 'x';
    size_t required;
    pattern.scale = 1;
    assert(!tryRenderDecimalDouble(0, pattern, symbols, output[], required));
    assert(output[0] == 'x' && required == 0);
}

@("Java special decimal values preserve the correct symbols and affixes")
unittest
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern("'p'0.00's';'n'0.00'z'", pattern) == DecimalCompileStatus.accepted);
    DecimalSymbolData symbols;
    symbols.nan = "undef";
    symbols.infinity = "∞!";
    char[24] output;
    size_t required;
    foreach (example; [
        SpecialValue(0x7ff8_0000_0000_0000, "undef"), SpecialValue(0xfff8_0000_0000_0000, "undef"),
        SpecialValue(0x7ff0_0000_0000_0000, "p∞!s"), SpecialValue(0xfff0_0000_0000_0000, "n∞!z"),
    ])
    {
        output[] = 'x';
        assert(tryRenderDecimalDouble(example.bits, pattern, symbols, output[0 .. 1], required),
                "special value was declined");
        assert(output[0] == 'x' && required == example.expected.length);
        assert(tryRenderDecimalDouble(example.bits, pattern, symbols, output[], required));
        assert(output[0 .. required] == example.expected && output[required] == 'x');
    }
}

private struct SpecialValue
{
    ulong bits;
    string expected;
}

@("Java pattern multipliers apply in binary64 before decimal rounding")
unittest
{
    static void check(string patternText, ulong bits, string expected)
    {
        DecimalFixedPattern pattern;
        assert(compileFixedDecimalPattern(patternText, pattern) == DecimalCompileStatus.accepted);
        DecimalSymbolData symbols;
        char[32] output;
        size_t required;
        assert(tryRenderDecimalDouble(bits, pattern, symbols, output[], required), "pattern multiplier was declined");
        assert(output[0 .. required] == expected);
    }

    check("0.00%", 0x4005_6666_6666_6666, "267.50%");
    check("0.00%;(0.00%)", 0xc005_6666_6666_6666, "(267.50%)");
    check("0.0‰", 0x4005_6666_6666_6666, "2675.0‰");
    check("0%", 0x7fef_ffff_ffff_ffff, "∞%");
    check("0%", 0xffef_ffff_ffff_ffff, "-∞%");
    check("0%", 0x8000_0000_0000_0000, "-0%");
    check("0%", 0xfff8_0000_0000_0000, "NaN");
}

@("Java grouped fixed-point keeps its binary64 half-even boundary")
unittest
{
    static void check(string text, ulong bits, string expected)
    {
        DecimalFixedPattern pattern;
        assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
        DecimalSymbolData symbols;
        char[48] output;
        output[] = 'x';
        size_t required;
        assert(tryRenderDecimalDouble(bits, pattern, symbols, output[0 .. 0], required),
                "grouped fast path was declined");
        assert(output[0] == 'x' && required == expected.length);
        assert(tryRenderDecimalDouble(bits, pattern, symbols, output[], required));
        assert(output[0 .. required] == expected);
    }

    check("#,##0.###", 0x3f40_624d_d2f1_a9fc, "0.001");
    check("#,##0.###", 0xbf40_624d_d2f1_a9fc, "-0.001");
    check("0.###", 0xbf40_624d_d2f1_a9fc, "-0");
    check("'p'#,##0.###'s';'n'#,##0.###'z'", 0xbf40_624d_d2f1_a9fc, "n0.001z");
    check("#,##0.###", 0x3fb0_0000_0000_0000, "0.062");
    check("#,##0.###", 0x3fc8_0000_0000_0000, "0.188");
    check("#,##0.###", 0x41df_ffff_ffc0_0000, "2,147,483,647");
    check("#,##0.###", 0x8000_0000_0000_0000, "-0");
}

@("Java explicit binary multipliers handle signed zeros, infinity and wide products")
unittest
{
    static void check(string text, int multiplier, ulong bits, string expected)
    {
        DecimalFixedPattern pattern;
        assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
        DecimalSymbolData symbols;
        char[64] output;
        output[] = 'x';
        size_t required;
        assert(tryRenderDecimalDouble(bits, multiplier, pattern, symbols, output[0 .. 0], required));
        assert(required == expected.length && output[0] == 'x');
        assert(tryRenderDecimalDouble(bits, multiplier, pattern, symbols, output[], required));
        assert(output[0 .. required] == expected && output[required] == 'x');
    }

    check("0.00%", -2, 0x3ff8_0000_0000_0000, "-3.00%");
    check("0.00%", -2, 0, "-0.00%");
    check("0.00%", -2, 0x8000_0000_0000_0000, "0.00%");
    check("0.00%", 0, 0x8000_0000_0000_0000, "-0.00%");
    check("0.00%", 0, 0x7ff0_0000_0000_0000, "NaN");
    check("0.00%", -1, 0x7ff0_0000_0000_0000, "-∞%");
    check("#,##0.###‰", 1, 0x3f40_624d_d2f1_a9fc, "0.001‰");
    check("0.000000000000000000", int.min, 0x3ff0_0000_0000_0001, "-2147483648.000000500000000000");
    check("0.000000000000000000", int.max, 0x3fff_ffff_ffff_ffff, "4294967293.999999500000000000");
}
