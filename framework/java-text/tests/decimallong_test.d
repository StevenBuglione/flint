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
