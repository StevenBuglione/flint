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
    assert(compileFixedDecimalPattern("#,##0.###", pattern) == DecimalCompileStatus.accepted);
    assert(!tryRenderDecimalDouble(0x3f40_624d_d2f1_a9fc, pattern, symbols, output[], required));
    assert(compileFixedDecimalPattern("0%", pattern) == DecimalCompileStatus.accepted);
    assert(!tryRenderDecimalDouble(0, pattern, symbols, output[], required));
    assert(compileFixedDecimalPattern("0", pattern) == DecimalCompileStatus.accepted);
    assert(!tryRenderDecimalDouble(0x7ff0_0000_0000_0000, pattern, symbols, output[], required));
    assert(output[0] == 'x' && required == 0);
}
