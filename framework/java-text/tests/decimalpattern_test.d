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

@("Fixed-point pattern validation rejects malformed digits")
unittest
{
    DecimalDigitSettings digits;
    foreach (pattern; ["0#", "0..0", "0.#0", "0,", "0.0,0"])
        assert(readDecimalDigits(pattern, digits) == DecimalDigitStatus.malformed);

    import std.array : replicate;

    const supported = "#," ~ "0".replicate(127);
    const wrapped = supported ~ "0";
    assert(readDecimalDigits(supported, digits) == DecimalDigitStatus.accepted && digits.groupingSize == 127);
    assert(readDecimalDigits(wrapped, digits) == DecimalDigitStatus.accepted && digits.groupingSize == 0);
}

@("Exponent pattern digit settings agree with Temurin")
unittest
{
    import std.array : replicate;

    const patterns = [
        "0.###E0", "##0.#####E0", "#E0", "0.0E00", "#,##0.0E0", "0.E0", ".##E0", "##00.00##E00",
        "0E" ~ "0".replicate(127), "0E" ~ "0".replicate(257), "0E" ~ "0".replicate(300),
    ];
    const expected = [
        DecimalDigitSettings(1, 0, 3, 0, false, 1, 1), DecimalDigitSettings(1, 0, 5, 0, false, 3,
                1), DecimalDigitSettings(0, 0, 0, 0, false, 1, 1),
        DecimalDigitSettings(1, 1, 1, 0, false, 1, 2), DecimalDigitSettings(1, 1, 1, 3, false, 4,
                1), DecimalDigitSettings(1, 0, 0, 0, true, 1, 1),
        DecimalDigitSettings(0, 1, 2, 0, true, 0, 1), DecimalDigitSettings(2, 2, 4, 0, false, 4,
                2), DecimalDigitSettings(1, 0, 0, 0, false, 1, 127),
        DecimalDigitSettings(1, 0, 0, 0, false, 1, 1), DecimalDigitSettings(1, 0, 0, 0, false, 1, 44),
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

@("Exponent patterns reject missing digits and Java's wrapped exponent widths")
unittest
{
    import std.array : replicate;

    DecimalDigitSettings digits;
    foreach (pattern; [".E0", "0E", "0.#0E0", "0,E0"])
        assert(readDecimalDigits(pattern, digits) == DecimalDigitStatus.malformed);
    foreach (zeros; [128, 255, 256])
        assert(readDecimalDigits("0E" ~ "0".replicate(zeros), digits) == DecimalDigitStatus.malformed);
}

@("The positive exponent ends after its zeros, leaving later text to the suffix")
unittest
{
    DecimalPatternBounds bounds;
    assert(scanDecimalPattern("0E0E", bounds) && !bounds.hasNegative);
    matches("0E0E", bounds.positive, "", "0E0", "E");
    assert(scanDecimalPattern("0.#E00'x';-0E0E#", bounds) && bounds.hasNegative);
    matches("0.#E00'x';-0E0E#", bounds.positive, "", "0.#E00", "'x'");
    matches("0.#E00'x';-0E0E#", bounds.negative, "-", "0E0E#", "");
}
