module flint.java.text.decimalpattern_long_test;

import flint.java.text.internal.decimalformatsymbols : decimalSymbolData;
import flint.java.text.internal.decimalfixed : DecimalFixedPattern, renderDecimalLong;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

@("Compiled DecimalFormat fixed-point patterns match Java's signed long formatting")
unittest
{
    const patterns = [
        "#,##0.00;(#,##0.00)", "#,##,##0.##", "0000.0##;'loss '0.0000", "0%;0'%'", "0%;0%",
        "0%;(0‰)", "'a'0;a0", "0%;", "0'%'%", "0-;0'-'", "", ".00", "0.",
        "'€😀;#'#,##0.00' units';('loss;'' '0.0000)", "'¤'0",
    ];
    const expected = [
        ["(9,223,372,036,854,775,808.00)", "(1.00)", "0.00", "1.00", "9,223,372,036,854,775,807.00"],
        ["-9,223,372,036,854,775,808", "-1", "0", "1", "9,223,372,036,854,775,807"],
        ["loss 9223372036854775808.0", "loss 0001.0", "0000.0", "0001.0",
            "9223372036854775807.0"],
        ["922337203685477580800%", "100%", "0%", "100%", "922337203685477580700%"],
        ["-922337203685477580800%", "-100%", "0%", "100%", "922337203685477580700%"],
        ["(922337203685477580800‰)", "(100‰)", "0%", "100%", "922337203685477580700%"],
        ["-a9223372036854775808", "-a1", "a0", "a1", "a9223372036854775807"],
        ["-922337203685477580800%", "-100%", "0%", "100%", "922337203685477580700%"],
        ["-922337203685477580800%%", "-100%%", "0%%", "100%%", "922337203685477580700%%"],
        ["9223372036854775808-", "1-", "0-", "1-", "9223372036854775807-"],
        ["-9,223,372,036,854,775,808", "-1", "0", "1", "9,223,372,036,854,775,807"],
        ["-9223372036854775808.00", "-1.00", ".00", "1.00", "9223372036854775807.00"],
        ["-9223372036854775808.", "-1.", "0.", "1.", "9223372036854775807."],
        [
            "(loss;' 9,223,372,036,854,775,808.00)", "(loss;' 1.00)", "€😀;#0.00 units",
            "€😀;#1.00 units", "€😀;#9,223,372,036,854,775,807.00 units"
        ], ["-¤9223372036854775808", "-¤1", "¤0", "¤1", "¤9223372036854775807"],
    ];
    const long[5] values = [long.min, -1, 0, 1, long.max];
    const symbols = decimalSymbolData("", "", "");
    foreach (i, text; patterns)
    {
        DecimalFixedPattern pattern;
        assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.accepted);
        char[80] output;
        foreach (j, value; values)
        {
            const written = renderDecimalLong(value, pattern, *symbols, output[]);
            assert(output[0 .. written] == expected[i][j], text);
        }
    }
}

@("DecimalFormat long composition distinguishes malformed and unsupported patterns")
unittest
{
    DecimalFixedPattern pattern;
    foreach (text; ["0;;", "'a';0", "0%%", "%0‰", "0'x", "0#"])
        assert(compileFixedDecimalPattern(text, pattern) == DecimalCompileStatus.malformed);
    assert(compileFixedDecimalPattern("0E00", pattern) == DecimalCompileStatus.exponential);
    assert(compileFixedDecimalPattern("¤0", pattern) == DecimalCompileStatus.currency);
    assert(compileFixedDecimalPattern("0x0", pattern) == DecimalCompileStatus.splitDigits);
}
