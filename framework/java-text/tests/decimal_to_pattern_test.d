/// DecimalFormat.toPattern and toLocalizedPattern of compiled patterns, and the empty pattern's fraction digits,
/// checked against Temurin 21.0.13+9 (decimal-to-pattern/unit-rows.tsv).
module flint.java.text.decimal_to_pattern_test;

import flint.java.text.internal.decimalfixed : DecimalFixedPattern;
import flint.java.text.internal.decimalfixedbinary : tryRenderDecimalDouble;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;
import flint.java.text.internal.decimalpattern : compileFixedDecimalPattern,
    compileLocalizedDecimalPattern, DecimalCompileStatus, synthesizeDecimalPattern;

@safe:

private DecimalSymbolData german() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.groupingSeparator = '.';
    symbols.decimalSeparator = ',';
    symbols.monetaryDecimalSeparator = ',';
    symbols.monetaryGroupingSeparator = '.';
    symbols.currencySymbol = "€";
    symbols.internationalCurrencySymbol = "EUR";
    return symbols;
}

private DecimalSymbolData arabic() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.zeroDigit = '٠';
    symbols.groupingSeparator = '٬';
    symbols.decimalSeparator = '٫';
    symbols.minusSign = '−';
    symbols.percent = '٪';
    symbols.perMill = '؉';
    symbols.digit = '•';
    symbols.patternSeparator = '؛';
    symbols.monetaryDecimalSeparator = '٫';
    symbols.monetaryGroupingSeparator = '٬';
    symbols.exponentSeparator = "×١٠^";
    symbols.currencySymbol = "ر.س";
    symbols.internationalCurrencySymbol = "SAR";
    return symbols;
}

// Localized symbols that are nonlocalized specials in other roles.
private DecimalSymbolData crossed() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.zeroDigit = '#';
    symbols.groupingSeparator = '.';
    symbols.decimalSeparator = ',';
    symbols.minusSign = ';';
    symbols.percent = '-';
    symbols.perMill = '%';
    symbols.digit = '0';
    symbols.patternSeparator = 'E';
    symbols.monetaryDecimalSeparator = ':';
    symbols.monetaryGroupingSeparator = '_';
    symbols.exponentSeparator = "e";
    symbols.currencySymbol = "$";
    symbols.internationalCurrencySymbol = "USD";
    return symbols;
}

// A quote digit and a currency-sign minus.
private DecimalSymbolData quoting() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.minusSign = '¤';
    symbols.percent = 'x';
    symbols.digit = '\'';
    symbols.patternSeparator = ' ';
    symbols.monetaryDecimalSeparator = '·';
    symbols.monetaryGroupingSeparator = '\'';
    symbols.exponentSeparator = "^";
    return symbols;
}

private DecimalSymbolData fullwidth() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.zeroDigit = '０';
    symbols.groupingSeparator = ' ';
    symbols.decimalSeparator = '·';
    symbols.minusSign = '−';
    symbols.digit = '*';
    symbols.patternSeparator = 'x';
    symbols.monetaryDecimalSeparator = '¸';
    symbols.monetaryGroupingSeparator = '０';
    symbols.exponentSeparator = "x😀";
    return symbols;
}

private void check(ref const DecimalSymbolData symbols, bool localized, string text, string pattern,
        string localizedPattern) pure nothrow
{
    DecimalFixedPattern compiled;
    const status = localized ? compileLocalizedDecimalPattern(text, symbols, compiled)
        : compileFixedDecimalPattern(text, symbols, compiled);
    assert(status == DecimalCompileStatus.accepted);
    string synthesized;
    assert(synthesizeDecimalPattern(compiled, symbols, false, synthesized));
    assert(synthesized == pattern);
    assert(synthesizeDecimalPattern(compiled, symbols, true, synthesized));
    assert(synthesized == localizedPattern);
}

@("toPattern quotes the affix patterns back and stops at the implicit negative")
unittest
{
    const DecimalSymbolData root;
    static void plain(string text, string expected) pure nothrow
    {
        const DecimalSymbolData latin;
        check(latin, false, text, expected, expected);
    }

    plain("#,##0.###", "#,##0.###");
    plain("0.", "#0.");
    plain("#,##,###", "#,###");
    plain("#,#00.0#", "#,#00.0#");
    plain("##0.##E0", "##0.##E0");
    plain("-0", "-#0");
    plain("'-'0", "'-'#0");
    plain("0;-0", "#0");
    plain("0.0;0.0", "#0.0");
    plain("a0b;a0b", "a#0b");
    plain("-0;--0", "-#0");
    plain("0;(0)", "#0;(#0)");
    plain("0;'-'0", "#0;'-'#0");
    // The separator-free pattern is read again as a negative subpattern without the exponent's suffix.
    plain("0E0E", "0E0E;0E0");
    plain("0‰;0‰", "#0‰");
    plain("0'%'%", "#0'%'%");
    plain("x'‰'0", "'x‰'#0");
    // The exponent separator is never quoted, so the literal reads back as an exponent.
    plain("0'E'", "#0E");
    plain("0'''x'", "#0''x");
    plain("' '0'#'", " #0'#'");
    plain("#,##0.00;'(#,##0.00)'", "#,##0.00;'(#,##0.00)'#,##0.00");
    plain("¤¤0", "¤¤#0");
    plain("¤'¤'0", "¤¤#0");
    plain("'¤'0", "'¤'#0");
    plain("¤ ¤¤0", "¤ ¤¤#0");
    plain("#,##0.00 ¤;-#,##0.00 '%x'", "#,##0.00 ¤;-#,##0.00' %x'");
    // The empty pattern allows int.max fraction digits, which Java's StringBuilder cannot hold.
    DecimalFixedPattern empty;
    assert(compileFixedDecimalPattern("", root, empty) == DecimalCompileStatus.accepted);
    string synthesized = "x";
    assert(!synthesizeDecimalPattern(empty, root, false, synthesized) && synthesized is null);
    assert(!synthesizeDecimalPattern(empty, root, true, synthesized));
}

@("toLocalizedPattern writes the localized symbols and the monetary separators of a currency pattern")
unittest
{
    const de = german();
    check(de, true, "#.##0,00 ¤", "#,##0.00 ¤", "#.##0,00 ¤");
    check(de, true, "0,0'.'%", "#0.0'.'%", "#0,0'.'%");
    const ar = arabic();
    check(ar, true, "'٬−٫'", "٬−٫#", "'٬−٫'•");
    check(ar, true, "٠٪", "#0%", "•٠٪");
    check(ar, true, "٫٠٠×١٠^٠'x'", ".00E0x", "٫٠٠×١٠^٠x");
    const cross = crossed();
    check(cross, true, "‰#", "'‰'#0", "‰0#");
    check(cross, true, "0###e#e", "#000E0e;#000E0", "0###e#eE0###e#");
    // A literal monetary decimal separator stays unquoted: Java checks the plain one.
    check(cross, true, ":#", ":#0", ":0#");
    // applyLocalizedPattern reads the plain separators; toLocalizedPattern writes the monetary ones.
    check(cross, true, "¤0.00#,##", "¤#,##0.00", "¤0_00#:##");
    const quote = quoting();
    check(quote, true, "','^0", "#,#E0", "','^0");
    // The quote digit is written unescaped.
    check(quote, true, "00 ", "#00", "'00");
    const wide = fullwidth();
    check(wide, true, "*·x😀０", "0.E0", "０·x😀０");
    check(wide, true, "０¤", "#0¤", "*０¤");
}

@("The empty pattern formats every fraction digit up to the double limit")
unittest
{
    DecimalFixedPattern pattern;
    const DecimalSymbolData symbols;
    assert(compileFixedDecimalPattern("", symbols, pattern) == DecimalCompileStatus.accepted);
    assert(pattern.minimumIntegerDigits == 0 && pattern.maximumFractionDigits == int.max);
    char[32] output;
    size_t required;
    // new DecimalFormat("").format(0.123456789)
    assert(tryRenderDecimalDouble(0x3fbf_9add_3739_635f, pattern, symbols, output[], required));
    assert(output[0 .. required] == ".123456789");
}
