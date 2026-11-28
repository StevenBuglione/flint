/// The public DecimalFormat over the private renderers, checked against Temurin 21.0.13+9 with ROOT symbols.
module flint.java.text.decimalformat_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.text.decimalformat : DecimalFormat;
import flint.java.text.decimalformatsymbols : DecimalFormatSymbols;
import flint.java.util : Locale;

@safe:

@("The default DecimalFormat uses the 0 pattern with the default symbols")
unittest
{
    auto format = new DecimalFormat();
    assert(format.toPattern() == "#0");
    assert(format.format(123) == "123");
    assert(format.format(-123) == "-123");
    assert(format.getDecimalFormatSymbols().getDecimalSeparator() == '.');
}

@("An explicit pattern compiles and formats longs and doubles")
unittest
{
    auto grouped = new DecimalFormat("#,##0");
    assert(grouped.format(1_234_567) == "1,234,567");
    assert(grouped.format(-1_234_567) == "-1,234,567");
    auto fixed = new DecimalFormat("0.00");
    assert(fixed.format(1.5) == "1.50");
    assert(fixed.format(1.234) == "1.23");
    auto percent = new DecimalFormat("0%");
    assert(percent.format(0.5) == "50%");
    auto exponent = new DecimalFormat("0.00E0");
    assert(exponent.format(1234) == "1.23E3");
}

@("applyPattern replaces the compiled pattern and toPattern round-trips")
unittest
{
    auto format = new DecimalFormat("0");
    format.applyPattern("0.000");
    assert(format.toPattern() == "#0.000");
    assert(format.format(1.5) == "1.500");
}

@("The digit-count accessors and setters track the compiled pattern")
unittest
{
    auto format = new DecimalFormat("0.00");
    assert(format.getMinimumIntegerDigits() == 1);
    assert(format.getMaximumIntegerDigits() == 2_147_483_647);
    assert(format.getMinimumFractionDigits() == 2);
    assert(format.getMaximumFractionDigits() == 2);
    format.setMinimumFractionDigits(3);
    assert(format.getMinimumFractionDigits() == 3);
    format.setMaximumIntegerDigits(4);
    assert(format.getMaximumIntegerDigits() == 4);
}

@("Grouping is on exactly when the interval is nonzero")
unittest
{
    auto format = new DecimalFormat("#,##0");
    assert(format.isGroupingUsed());
    assert(format.getGroupingSize() == 3);
    format.setGroupingUsed(false);
    assert(!format.isGroupingUsed());
    format.setGroupingUsed(true);
    assert(format.isGroupingUsed());
    assert(format.getGroupingSize() == 3);
}

@("Turning grouping off suppresses separators but keeps the interval")
unittest
{
    auto format = new DecimalFormat("#,##0");
    format.setGroupingUsed(false);
    assert(format.format(1_234_567) == "1234567");
    assert(format.getGroupingSize() == 3);
    format.setGroupingUsed(true);
    assert(format.format(1_234_567) == "1,234,567");
}

@("The multiplier follows the percent and per-mille signs")
unittest
{
    assert(new DecimalFormat("0").getMultiplier() == 1);
    assert(new DecimalFormat("0%").getMultiplier() == 100);
    assert(new DecimalFormat("0‰").getMultiplier() == 1000);
}

@("A lone-surrogate symbol is rejected at applyPattern, not passed to the renderer")
unittest
{
    auto format = new DecimalFormat("0");
    auto symbols = format.getDecimalFormatSymbols();
    symbols.setZeroDigit(cast(wchar) 0xD800);
    format.setDecimalFormatSymbols(symbols);
    bool threw;
    try
        format.applyPattern("0");
    catch (IllegalArgumentException)
        threw = true;
    assert(threw);
}

@("getDecimalFormatSymbols returns an independent copy and setDecimalFormatSymbols replaces them")
unittest
{
    auto format = new DecimalFormat("0");
    auto copy = format.getDecimalFormatSymbols();
    copy.setZeroDigit('1');
    assert(format.getDecimalFormatSymbols().getZeroDigit() == '0');
    format.setDecimalFormatSymbols(copy);
    assert(format.getDecimalFormatSymbols().getZeroDigit() == '1');
    auto us = DecimalFormatSymbols.getInstance(Locale.US);
    format.setDecimalFormatSymbols(us);
    assert(format.getDecimalFormatSymbols().getCurrencySymbol() == "$");
}
