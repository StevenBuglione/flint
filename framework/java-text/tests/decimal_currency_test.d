/// DecimalFormat currency patterns, checked against Temurin 21.0.13+9 (decimal-currency/unit-rows.tsv).
module flint.java.text.decimal_currency_test;

import flint.java.text.internal.decimalfixed : DecimalField, DecimalFieldSpans,
    DecimalFixedPattern, renderDecimalLong;
import flint.java.text.internal.decimalfixedbinary : tryRenderDecimalDouble;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, decimalSymbolData;
import flint.java.text.internal.decimalparse : DecimalParseKind, DecimalParseOptions, parseDecimal;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern;

@safe:

private DecimalSymbolData euro() pure nothrow @nogc
{
    DecimalSymbolData symbols;
    symbols.monetaryDecimalSeparator = ',';
    symbols.monetaryGroupingSeparator = '.';
    symbols.currencySymbol = "€";
    symbols.internationalCurrencySymbol = "EUR";
    return symbols;
}

private DecimalFixedPattern compile(string text, ref const DecimalSymbolData symbols) pure nothrow
{
    DecimalFixedPattern pattern;
    assert(compileFixedDecimalPattern(text, symbols, pattern) == DecimalCompileStatus.accepted);
    return pattern;
}

private string renderLong(long value, string text, ref const DecimalSymbolData symbols) pure nothrow
{
    const pattern = compile(text, symbols);
    auto output = new char[64];
    const required = renderDecimalLong(value, 1, pattern, symbols, output);
    assert(required <= output.length);
    return output[0 .. required].idup;
}

private string renderDouble(ulong bits, string text, ref const DecimalSymbolData symbols) pure nothrow
{
    const pattern = compile(text, symbols);
    auto output = new char[64];
    size_t required;
    assert(tryRenderDecimalDouble(bits, pattern, symbols, output, required));
    return output[0 .. required].idup;
}

@("ROOT and English show the generic currency sign; US shows the dollar") unittest
{
    static void check() pure nothrow @nogc
    {
        const root = decimalSymbolData("", "", "");
        assert(root is decimalSymbolData("en", "", ""));
        assert(root.currencySymbol == "¤" && root.internationalCurrencySymbol == "XXX");
        const us = decimalSymbolData("en", "US", "");
        assert(us !is null && us !is root);
        assert(us.currencySymbol == "$" && us.internationalCurrencySymbol == "USD");
        assert(us.decimalSeparator == '.' && us.monetaryDecimalSeparator == '.' && us.monetaryGroupingSeparator == ',');
    }

    check();
}

@("Currency signs expand to the symbol, the code, or the code after a quoted sign") unittest
{
    const us = *decimalSymbolData("en", "US", "");
    auto pattern = compile("¤#,##0.00", us);
    assert(pattern.currencyFormat && !pattern.affixFieldsShifted);
    assert(pattern.positive.prefix == "$" && pattern.negative.prefix == "-$");
    assert(pattern.positive.prefixFields == [DecimalField.currency, 0, 1]);
    assert(compile("¤¤0", us).positive.prefix == "USD");
    assert(compile("¤¤¤0", us).positive.prefix == "USD$");
    assert(compile("¤¤¤¤0", us).positive.prefix == "USDUSD");
    // expandAffix reads the quoted sign after an unquoted one as the doubled form.
    assert(compile("¤'¤'0", us).positive.prefix == "USD");
    assert(compile("¤'''¤'0", us).positive.prefix == "$'¤");
    const literal = compile("'¤'0", us);
    assert(literal.positive.prefix == "¤" && !literal.currencyFormat && literal.positive.prefixFields.length == 0);
    assert(renderLong(-1234, "¤'¤'0", us) == "-USD1234");

    DecimalFieldSpans spans;
    auto output = new char[16];
    const tripled = compile("¤¤¤0", us);
    const required = renderDecimalLong(1, 1, tripled, us, output, &spans);
    assert(output[0 .. required] == "USD$1");
    assert(spans.spans[DecimalField.currency].recorded
            && spans.spans[DecimalField.currency].begin == 0 && spans.spans[DecimalField.currency].end == 3);
}

@("A currency pattern uses the monetary separators, even when only the negative subpattern has the sign")
unittest
{
    const symbols = euro();
    assert(renderLong(-1_234_567, "¤#,##0.00", symbols) == "-€1.234.567,00");
    assert(renderLong(-1_234_567, "#,##0.00", symbols) == "-1,234,567.00");
    assert(renderDouble(0x3ff8_0000_0000_0000, "0.00;¤0", symbols) == "1,50");
}

@("The negative subpattern repeats the positive one only when the affix patterns match") unittest
{
    DecimalSymbolData chf;
    chf.currencySymbol = "CHF";
    chf.internationalCurrencySymbol = "CHF";
    assert(renderLong(-1, "¤0;¤¤0", chf) == "CHF1");
    assert(renderLong(-1, "¤0;¤0", chf) == "-CHF1");

    DecimalSymbolData empty;
    empty.currencySymbol = "";
    empty.internationalCurrencySymbol = "XTS";
    assert(renderLong(-1, "¤0;0", empty) == "1");
    // A doubled quote stays in the affix pattern, and quoting a literal does not.
    const root = *decimalSymbolData("", "", "");
    assert(renderLong(-1, "''0;0", root) == "1");
    assert(renderLong(-1, "'x'0;x0", root) == "-x1");
    assert(renderLong(-1, "¤0", empty) == "-1");
    // Java reports the sign after an empty symbol one unit late (1:2 in "-1"); field reporting defers.
    assert(compile("¤-0", empty).affixFieldsShifted);
    assert(!compile("¤0", empty).affixFieldsShifted && !compile("-¤0", empty).affixFieldsShifted);
}

@("The grouped fast path keeps two places for currency and skips a currency pattern with three") unittest
{
    const us = *decimalSymbolData("en", "US", "");
    assert(renderDouble(0x4005_6666_6666_6666, "¤#,##0.00", us) == "$2.67");
    assert(renderDouble(0x3f40_624d_d2f1_a9fc, "#,##0.###¤", us) == "0$");
    assert(renderDouble(0x3f40_624d_d2f1_a9fc, "#,##0.###", us) == "0.001");
}

@("Parsing a currency pattern reads the monetary separators") unittest
{
    const symbols = euro();
    const pattern = compile("¤#,##0.00", symbols);
    char[32] digits;
    auto result = parseDecimal("€1.234,5", 0, pattern, symbols, DecimalParseOptions.init, digits[]);
    assert(result.kind == DecimalParseKind.doubleValue && result.doubleValue == 1234.5 && result.index == 10);
    result = parseDecimal("€1,234.5", 0, pattern, symbols, DecimalParseOptions.init, digits[]);
    assert(result.kind == DecimalParseKind.doubleValue && result.doubleValue == 1.234 && result.index == 8);
}
