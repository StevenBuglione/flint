/// The public DecimalFormatSymbols over the pinned symbol data. The internal fixtures live in
/// decimalformatsymbols_test.
module flint.java.text.decimal_formatsymbols_public_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.text.decimalformatsymbols : DecimalFormatSymbols;
import flint.java.util : Locale;

@safe:

@("ROOT, English and US instances expose the pinned symbols") unittest
{
    foreach (locale; [Locale.ROOT, Locale.ENGLISH, Locale.US])
    {
        auto symbols = DecimalFormatSymbols.getInstance(locale);
        assert(symbols.getZeroDigit() == '0');
        assert(symbols.getDecimalSeparator() == '.');
        assert(symbols.getGroupingSeparator() == ',');
        assert(symbols.getPerMill() == '\u2030');
        assert(symbols.getPercent() == '%');
        assert(symbols.getDigit() == '#');
        assert(symbols.getPatternSeparator() == ';');
        assert(symbols.getMinusSign() == '-');
        assert(symbols.getMonetaryDecimalSeparator() == '.');
        assert(symbols.getMonetaryGroupingSeparator() == ',');
        assert(symbols.getExponentSeparator() == "E");
        assert(symbols.getInfinity() == "∞");
        assert(symbols.getNaN() == "NaN");
    }
}

@("US carries the dollar currency; ROOT and English carry the generic sign") unittest
{
    auto us = DecimalFormatSymbols.getInstance(Locale.US);
    assert(us.getCurrencySymbol() == "$");
    assert(us.getInternationalCurrencySymbol() == "USD");
    auto root = DecimalFormatSymbols.getInstance(Locale.ROOT);
    assert(root.getCurrencySymbol() == "¤");
    assert(root.getInternationalCurrencySymbol() == "XXX");
}

@("An unsupported locale is rejected by name") unittest
{
    bool threw;
    try
        DecimalFormatSymbols.getInstance(Locale.FRENCH);
    catch (IllegalArgumentException)
        threw = true;
    assert(threw);
}

@("A copy is independent of the original") unittest
{
    auto original = DecimalFormatSymbols.getInstance(Locale.US);
    auto copy = original.copy();
    copy.setZeroDigit('1');
    assert(copy.getZeroDigit() == '1');
    assert(original.getZeroDigit() == '0');
}
