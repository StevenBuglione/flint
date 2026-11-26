/// Fixed-point signed long rows from Temurin 21.0.13+9.
module flint.java.text.decimallong_test;

import flint.java.text.internal.decimalfixed : DecimalAffixes, DecimalFixedPattern, renderDecimalLong;
import flint.java.text.internal.decimalformatsymbols : decimalSymbolData;

@safe:

@("Fixed-point DecimalFormat long rendering agrees with Temurin at both signed limits")
unittest
{
    auto symbols = decimalSymbolData("", "", "");
    DecimalFixedPattern[6] patterns;
    patterns[0].groupingSize = 3;
    patterns[0].minimumFractionDigits = 2;
    patterns[0].negative = DecimalAffixes("(", ")");
    patterns[1].groupingSize = 3;
    patterns[2].minimumIntegerDigits = 4;
    patterns[2].minimumFractionDigits = 1;
    patterns[2].negative.prefix = "loss ";
    patterns[3].positive.suffix = "%";
    patterns[3].negative.suffix = "%";
    patterns[4] = patterns[3];
    patterns[4].scale = 2;

    immutable long[5] values = [long.min, -1234, 0, 1234, long.max];
    immutable string[5][6] expected = [
        [
            "(9,223,372,036,854,775,808.00)", "(1,234.00)", "0.00", "1,234.00",
            "9,223,372,036,854,775,807.00"
        ], ["-9,223,372,036,854,775,808", "-1,234", "0", "1,234", "9,223,372,036,854,775,807"],
        ["loss 9223372036854775808.0", "loss 1234.0", "0000.0", "1234.0",
            "9223372036854775807.0"],
        ["-9223372036854775808%", "-1234%", "0%", "1234%", "9223372036854775807%"],
        ["-922337203685477580800%", "-123400%", "0%", "123400%", "922337203685477580700%"],
        ["-9223372036854775808", "-1234", "0", "1234", "9223372036854775807"],
    ];
    char[80] output;
    foreach (i, ref pattern; patterns)
    {
        foreach (j, value; values)
        {
            const used = renderDecimalLong(value, pattern, *symbols, output[]);
            assert(output[0 .. used] == expected[i][j]);
        }
    }
}

@("Fixed-point long rendering preserves UTF-8 affixes and does not partially write a short buffer")
unittest
{
    auto symbols = decimalSymbolData("en", "", "");
    DecimalFixedPattern pattern;
    pattern.groupingSize = 3;
    pattern.positive = DecimalAffixes("€😀", "‰");
    pattern.scale = 3;
    enum expected = "€😀1,234,000‰";
    char[expected.length + 1] output;
    output[] = 'x';
    const required = renderDecimalLong(1234, pattern, *symbols, output[0 .. 1]);
    assert(required == expected.length);
    foreach (value; output)
        assert(value == 'x');
    const written = renderDecimalLong(1234, pattern, *symbols, output[]);
    assert(written == required && output[0 .. written] == expected);
    assert(output[written] == 'x');
}

@("A zero integer part can be omitted when fractional digits are required")
unittest
{
    auto symbols = decimalSymbolData("en", "US", "");
    DecimalFixedPattern pattern;
    pattern.minimumIntegerDigits = 0;
    pattern.minimumFractionDigits = 2;
    char[4] output;
    const fractional = renderDecimalLong(0, pattern, *symbols, output[]);
    assert(output[0 .. fractional] == ".00");

    pattern = DecimalFixedPattern.init;
    pattern.decimalSeparatorAlwaysShown = true;
    const integral = renderDecimalLong(7, pattern, *symbols, output[]);
    assert(output[0 .. integral] == "7.");
}

@("Java explicit long multipliers preserve the full product and clear zero's sign")
unittest
{
    import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

    static void check(string text, long value, int multiplier, string expected)
    {
        DecimalFixedPattern pattern;
        assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
        auto symbols = decimalSymbolData("", "", "");
        char[64] output;
        output[] = 'x';
        const required = renderDecimalLong(value, multiplier, pattern, *symbols, output[0 .. 0]);
        assert(required == expected.length && output[0] == 'x');
        const written = renderDecimalLong(value, multiplier, pattern, *symbols, output[]);
        assert(written == required && output[0 .. written] == expected && output[written] == 'x');
    }

    check("0", long.min, int.min, "19807040628566084398385987584");
    check("#,##0.00%", long.min, int.min, "19,807,040,628,566,084,398,385,987,584.00%");
    check("0", long.min, 0, "0");
    check("#,##0.00%", 123, 1, "123.00%");
    check("#,##0.00%", 123, -2, "-246.00%");
    check("'p'0's';'n'0'z'", 0, -2, "p0s");
}

@("Integer width keeps the low digits and couples maximum and minimum")
unittest
{
    auto symbols = decimalSymbolData("", "", "");
    DecimalFixedPattern pattern;
    pattern.groupingSize = 3;
    pattern.minimumFractionDigits = 2;
    char[320] output;
    output[] = 'x';
    pattern.setMinimumIntegerDigits(5);
    pattern.setMaximumIntegerDigits(3);
    assert(pattern.minimumIntegerDigits == 3);
    const required = renderDecimalLong(-12_345, pattern, *symbols, output[0 .. 1]);
    assert(required == 7 && output[0] == 'x');
    auto written = renderDecimalLong(-12_345, pattern, *symbols, output[]);
    assert(output[0 .. written] == "-345.00" && output[written] == 'x');

    pattern.setMaximumIntegerDigits(-1);
    assert(pattern.minimumIntegerDigits == 0 && pattern.maximumIntegerDigits == 0);
    written = renderDecimalLong(12_345, pattern, *symbols, output[]);
    assert(output[0 .. written] == ".00");
    pattern.minimumFractionDigits = 0;
    written = renderDecimalLong(-12_345, pattern, *symbols, output[]);
    assert(output[0 .. written] == "-0");

    pattern.groupingSize = 0;
    pattern.setMinimumIntegerDigits(500);
    assert(pattern.maximumIntegerDigits == 500);
    written = renderDecimalLong(42, pattern, *symbols, output[]);
    assert(written == 309 && output[307 .. 309] == "42");
    foreach (digit; output[0 .. 307])
        assert(digit == '0');
}

@("Long fraction padding uses the coupled Java widths and a 340-digit primitive limit")
unittest
{
    auto symbols = decimalSymbolData("", "", "");
    DecimalFixedPattern pattern;
    char[350] output;
    output[] = 'x';

    pattern.setMinimumFractionDigits(4);
    assert(pattern.maximumFractionDigits == 4);
    auto written = renderDecimalLong(42, pattern, *symbols, output[]);
    assert(output[0 .. written] == "42.0000" && output[written] == 'x');

    pattern.setMaximumFractionDigits(-1);
    assert(pattern.minimumFractionDigits == 0 && pattern.maximumFractionDigits == 0);
    written = renderDecimalLong(42, pattern, *symbols, output[]);
    assert(output[0 .. written] == "42");

    pattern.setMinimumFractionDigits(500);
    assert(pattern.minimumFractionDigits == 500 && pattern.maximumFractionDigits == 500);
    output[] = 'x';
    const required = renderDecimalLong(42, pattern, *symbols, output[0 .. 1]);
    assert(required == 343 && output[0] == 'x');
    written = renderDecimalLong(42, pattern, *symbols, output[]);
    assert(written == required && output[0 .. 3] == "42." && output[written] == 'x');
    foreach (digit; output[3 .. written])
        assert(digit == '0');
}
