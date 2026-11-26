/// Decimal floating-point rendering for Java Formatter.
module flint.java.util.internal.formatter_decimal;

import flint.engine.aot.text : decimal;
import flint.java.util.internal.formatter_support : Flag, FormatOptions, asciiLower;
import flint.java.util.internal.formatter_float_special : nonFinite;
import flint.java.util.internal.formatter_number_padding : signed;

@safe:

/// Render a validated value in fixed, scientific or general notation.
package(flint.java) string formatDecimal(const ref FormatOptions spec, double value)
{
    const uppercase = asciiLower(spec.conversion) != spec.conversion;
    const negative = value < 0 || (value == 0 && 1 / value < 0);
    if (value != value || value == double.infinity || value == -double.infinity)
        return nonFinite(spec, value, negative, uppercase);
    const magnitude = negative ? -value : value;
    const precision = spec.precision < 0 ? 6 : spec.precision;
    const text = spec.conversion == 'f' ? fixedMagnitude(spec, magnitude,
            precision) : significantMagnitude(spec, magnitude, precision);
    return signed(spec, text, negative);
}

private string fixedMagnitude(const ref FormatOptions spec, double magnitude, int precision)
{
    string whole, fraction;
    decimalDigits(magnitude, whole, fraction);
    roundHalfUp(whole, fraction, precision);
    return plainText(spec, whole, fraction);
}

private string plainText(const ref FormatOptions spec, string whole, string fraction)
{
    const integer = spec.has(Flag.group) ? grouped(whole) : whole;
    return fraction.length != 0 || spec.has(Flag.alternate) ? integer ~ "." ~ fraction : integer;
}

private string significantMagnitude(const ref FormatOptions spec, double magnitude, int precision)
{
    const general = asciiLower(spec.conversion) == 'g';
    const significantDigits = precision == 0 ? 1 : precision;
    string whole, fraction;
    const exponent = roundedMantissa(magnitude, general ? significantDigits - 1 : precision, whole, fraction);
    // General notation is selected using the exponent after rounding.
    if (general && exponent >= -4 && exponent < significantDigits)
        return generalPlainText(spec, whole, fraction, exponent);
    return scientificText(spec, whole, fraction, exponent);
}

private string generalPlainText(const ref FormatOptions spec, string whole, string fraction, int exponent)
{
    if (exponent < 0)
        return "0." ~ "000"[0 .. -exponent - 1] ~ whole ~ fraction;
    const significand = whole ~ fraction;
    const point = exponent + 1;
    return plainText(spec, significand[0 .. point], significand[point .. $]);
}

/// Round a single leading digit and its fractional digits and return the adjusted exponent.
private int roundedMantissa(double magnitude, int precision, out string whole, out string fraction)
{
    ptrdiff_t point;
    auto significand = decimalSignificand(magnitude, point);
    while (significand.length > 1 && significand[0] == '0')
    {
        significand = significand[1 .. $];
        --point;
    }
    int exponent = magnitude == 0 ? 0 : cast(int) point - 1;
    whole = significand[0 .. 1];
    fraction = significand[1 .. $];
    roundHalfUp(whole, fraction, precision);
    if (whole.length > 1)
    {
        ++exponent;
        whole = whole[0 .. 1]; // A mantissa of 10 becomes 1 with the next exponent.
    }
    return exponent;
}

private string scientificText(const ref FormatOptions spec, string whole, string fraction, int exponent)
{
    const separator = fraction.length != 0 || spec.has(Flag.alternate) ? "." : "";
    const marker = asciiLower(spec.conversion) == spec.conversion ? "e" : "E";
    const sign = exponent < 0 ? "-" : "+";
    const exponentDigits = decimal(exponent < 0 ? -exponent : exponent);
    const leadingZero = exponentDigits.length == 1 ? "0" : "";
    return whole ~ separator ~ fraction ~ marker ~ sign ~ leadingZero ~ exponentDigits;
}

/// The whole and fraction digits of `magnitude` from Java's shortest representation (`Double.toString`), which
/// Java's `Formatter` rounds from (a `float` is widened to `double` first, as Java does).
private void decimalDigits(double magnitude, out string whole, out string fraction)
{
    ptrdiff_t position;
    auto digitText = decimalSignificand(magnitude, position);
    while (position <= 0)
    {
        digitText = "0" ~ digitText;
        position++;
    }
    while (position > digitText.length)
        digitText ~= '0';
    whole = digitText[0 .. position];
    fraction = digitText[position .. $];
    while (whole.length > 1 && whole[0] == '0')
        whole = whole[1 .. $];
}

/// The shortest decimal digits and the point position after applying any exponent.
private string decimalSignificand(double magnitude, out ptrdiff_t position)
{
    import flint.java.lang : doubleToString;

    const text = doubleToString(magnitude);
    size_t e;
    while (e < text.length && text[e] != 'E')
        e++;
    long exponent;
    if (e < text.length)
    {
        const negativeExponent = text[e + 1] == '-';
        exponent = number(text[e + (negativeExponent ? 2 : 1) .. $]);
        if (negativeExponent)
            exponent = -exponent;
    }
    string digitText;
    ptrdiff_t point = -1;
    foreach (c; text[0 .. e])
    {
        if (c == '.')
            point = cast(ptrdiff_t) digitText.length;
        else
            digitText ~= c;
    }
    position = (point < 0 ? cast(ptrdiff_t) digitText.length : point) + exponent;
    return digitText;
}

/// Round `whole.fraction` to `precision` fraction digits, half up, as Java's `RoundingMode.HALF_UP`.
private void roundHalfUp(ref string whole, ref string fraction, int precision) pure nothrow
{
    if (fraction.length <= precision)
    {
        while (fraction.length < precision)
            fraction ~= '0';
        return;
    }
    const up = fraction[precision] >= '5';
    auto digits = (whole ~ fraction[0 .. precision]).dup;
    if (up)
    {
        size_t i = digits.length;
        while (i > 0 && digits[i - 1] == '9')
            digits[--i] = '0';
        if (i == 0)
            digits = "1".dup ~ digits;
        else
            digits[i - 1]++;
    }
    whole = digits[0 .. $ - precision].idup;
    fraction = digits[$ - precision .. $].idup;
}

/// Decimal digits with `,` every three from the right.
private string grouped(string digitText) pure nothrow
{
    string result;
    foreach (i, c; digitText)
    {
        if (i && (digitText.length - i) % 3 == 0)
            result ~= ',';
        result ~= c;
    }
    return result;
}

private long number(string digits) pure nothrow @nogc
{
    long value;
    foreach (c; digits)
        value = value * 10 + (c - '0');
    return value;
}
