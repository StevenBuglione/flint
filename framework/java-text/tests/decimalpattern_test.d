module flint.java.text.decimalpattern_test;

import flint.java.text.internal.decimalpattern : DecimalDigitSettings, DecimalDigitStatus,
    DecimalPatternBounds, DecimalSubpatternBounds, readDecimalDigits, scanDecimalPattern;

@safe:

private void matches(string text, DecimalSubpatternBounds part, string prefix, string digits, string suffix)
{
    assert(text[part.start .. part.digitsStart] == prefix);
    assert(text[part.digitsStart .. part.digitsEnd] == digits);
    assert(text[part.digitsEnd .. part.end] == suffix);
}

@("DecimalFormat pattern bounds preserve separately quoted positive and negative affixes")
unittest
{
    DecimalPatternBounds bounds;
    enum text = "'€😀;#'#,##0.00' units';('loss;'' '0.0000)";
    assert(scanDecimalPattern(text, bounds) && bounds.hasNegative);
    matches(text, bounds.positive, "'€😀;#'", "#,##0.00", "' units'");
    matches(text, bounds.negative, "('loss;'' '", "0.0000", ")");
}

@("DecimalFormat pattern lexer keeps significant syntax for semantic validation")
unittest
{
    DecimalPatternBounds bounds;
    assert(scanDecimalPattern("#,##,##0.##", bounds) && !bounds.hasNegative);
    matches("#,##,##0.##", bounds.positive, "", "#,##,##0.##", "");
    assert(scanDecimalPattern("0E00%", bounds) && !bounds.hasNegative);
    matches("0E00%", bounds.positive, "", "0E00", "%");
    assert(scanDecimalPattern("''E.00';'‰", bounds) && !bounds.hasNegative);
    matches("''E.00';'‰", bounds.positive, "''E", ".00", "';'‰");
    assert(scanDecimalPattern("0;", bounds) && bounds.hasNegative);
    matches("0;", bounds.negative, "", "", "");
    assert(scanDecimalPattern("", bounds) && !bounds.hasNegative);
    matches("", bounds.positive, "", "", "");
}

@("DecimalFormat pattern lexer rejects unterminated affixes and multiple unquoted separators")
unittest
{
    DecimalPatternBounds bounds;
    assert(!scanDecimalPattern("0'x", bounds));
    assert(!scanDecimalPattern("'x0", bounds));
    assert(!scanDecimalPattern("0;0;0", bounds));
    assert(!scanDecimalPattern("0;0'x", bounds));
}

@("Positive fixed-point digit settings agree with Temurin")
unittest
{
    const patterns = [
        "#,##0.00;(#,##0.00)", "#,##,##0.##", "0000.0##;'loss '0.0000", "##.###", ".###", "###.",
        ".00", "0.", "####", "."
    ];
    const expected = [
        DecimalDigitSettings(1, 2, 2, 3, false), DecimalDigitSettings(1, 0, 2, 3, false),
        DecimalDigitSettings(4, 1, 3, 0, false), DecimalDigitSettings(1, 0, 3, 0, false),
        DecimalDigitSettings(0, 1, 3, 0, true), DecimalDigitSettings(1, 0, 0, 0, true),
        DecimalDigitSettings(0, 2, 2, 0, true), DecimalDigitSettings(1, 0, 0, 0, true),
        DecimalDigitSettings(0, 0, 0, 0, false), DecimalDigitSettings(0, 0, 0, 0, true),
    ];
    foreach (i, text; patterns)
    {
        DecimalPatternBounds bounds;
        assert(scanDecimalPattern(text, bounds));
        DecimalDigitSettings digits;
        assert(readDecimalDigits(text[bounds.positive.digitsStart .. bounds.positive.digitsEnd],
                digits) == DecimalDigitStatus.accepted);
        assert(digits == expected[i]);
    }
}

@("Fixed-point pattern validation distinguishes exponents and malformed digits")
unittest
{
    DecimalDigitSettings digits;
    foreach (pattern; ["0#", "0..0", "0.#0", "0,", "0.0,0"])
        assert(readDecimalDigits(pattern, digits) == DecimalDigitStatus.malformed);
    assert(readDecimalDigits("0E00", digits) == DecimalDigitStatus.exponential);

    import std.array : replicate;

    const supported = "#," ~ "0".replicate(127);
    const wrapped = supported ~ "0";
    assert(readDecimalDigits(supported, digits) == DecimalDigitStatus.accepted && digits.groupingSize == 127);
    assert(readDecimalDigits(wrapped, digits) == DecimalDigitStatus.accepted && digits.groupingSize == 0);
}
