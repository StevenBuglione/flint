/// Hexadecimal floating-point rendering for Java Formatter.
module flint.java.util.internal.formatter_hex_float;

import flint.engine.aot.text : decimal;
import flint.java.util.internal.formatter_support : Flag, FormatOptions, asciiLower;
import flint.java.util.internal.formatter_float_special : nonFinite;
import flint.java.util.internal.formatter_number_padding : numberSign, numberZeros;

@safe:

/// Render a validated value in hexadecimal scientific notation.
package(flint.java) string formatHexFloat(const ref FormatOptions spec, double value)
{
    const uppercase = asciiLower(spec.conversion) != spec.conversion;
    const negative = value < 0 || (value == 0 && 1 / value < 0);
    if (value != value || value == double.infinity || value == -double.infinity)
        return nonFinite(spec, value, negative, uppercase);
    const magnitude = negative ? -value : value;
    return hexadecimalFloatingText(spec, magnitude, negative, uppercase);
}

private union HexDoubleBits
{
    double value;
    ulong bits;
}

private enum doubleHiddenBit = 1UL << 52;
private enum hexFractionDigits = 13;

private string hexadecimalFloatingText(const ref FormatOptions spec, double magnitude, bool negative, bool uppercase)
{
    const precision = spec.precision == 0 ? 1 : spec.precision;
    int exponent;
    const mantissa = hexFloatMantissa(magnitude, precision, uppercase, exponent);
    const ending = (uppercase ? "P" : "p") ~ decimal(exponent);
    const sign = numberSign(spec, negative);
    const prefix = uppercase ? "0X" : "0x";

    // Java measures width padding before adding any fractional zeros requested by precision.
    const used = sign.length + prefix.length + mantissa.length + ending.length;
    const widthZeros = spec.has(Flag.zero) && spec.width > 0 && cast(size_t) spec.width > used
        ? numberZeros(spec.width - used) : "";
    const present = cast(int) mantissa.length - 2;
    const precisionZeros = precision > present ? numberZeros(precision - present) : "";
    return sign ~ prefix ~ widthZeros ~ mantissa ~ precisionZeros ~ ending;
}

private string hexFloatMantissa(double magnitude, int precision, bool uppercase, out int exponent)
{
    HexDoubleBits data;
    data.value = magnitude;
    const encodedExponent = cast(int)((data.bits >> 52) & 0x7ff);
    ulong significand = data.bits & (doubleHiddenBit - 1);
    if (encodedExponent != 0)
    {
        significand |= doubleHiddenBit;
        exponent = encodedExponent - 1023;
    }
    else if (significand != 0)
        exponent = -1022;

    if (significand != 0 && precision > 0 && precision < hexFractionDigits)
        significand = roundHexSignificand(significand, precision, exponent);

    char[2 + hexFractionDigits] buffer;
    buffer[0] = (significand & doubleHiddenBit) != 0 ? '1' : '0';
    buffer[1] = '.';
    const alphabet = uppercase ? "0123456789ABCDEF" : "0123456789abcdef";
    foreach (i; 0 .. hexFractionDigits)
    {
        const shift = 4 * (hexFractionDigits - 1 - i);
        buffer[i + 2] = alphabet[(significand >> shift) & 0xF];
    }
    size_t end = buffer.length;
    while (end > 3 && buffer[end - 1] == '0')
        --end;
    return buffer[0 .. end].idup;
}

private ulong roundHexSignificand(ulong significand, int precision, ref int exponent) pure nothrow @nogc
{
    while ((significand & doubleHiddenBit) == 0)
    {
        significand <<= 1;
        --exponent;
    }
    const discard = 4 * (hexFractionDigits - precision);
    const halfway = 1UL << (discard - 1);
    const remainder = significand & ((1UL << discard) - 1);
    auto retained = significand >> discard;
    if (remainder > halfway || (remainder == halfway && (retained & 1) != 0))
        ++retained;
    auto rounded = retained << discard;
    if ((rounded & (doubleHiddenBit << 1)) != 0)
    {
        rounded >>= 1;
        ++exponent;
    }
    return rounded;
}
