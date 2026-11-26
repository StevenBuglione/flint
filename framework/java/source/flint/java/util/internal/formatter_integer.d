/// Integral rendering for Java Formatter.
module flint.java.util.internal.formatter_integer;

import flint.java.util.internal.formatter_support : Flag, FormatOptions, asciiUppercase;
import flint.java.util.internal.formatter_digits : digits;
import flint.java.util.internal.formatter_number_padding : paddedNumber, signed;

@safe:

/// Render a validated integral value in decimal.
package(flint.java) string formatIntegral(const ref FormatOptions spec, long value, bool unsigned) pure nothrow
{
    const negative = !unsigned && value < 0;
    const magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    return signed(spec, digits(magnitude, 10, spec.has(Flag.group)), negative);
}

/// Render the bit width already selected by the caller for octal or hexadecimal output.
package(flint.java) string formatRadix(const ref FormatOptions spec, ulong bits) pure nothrow
{
    const octal = spec.conversion == 'o';
    const magnitude = digits(bits, octal ? 8 : 16, false);
    const prefix = spec.has(Flag.alternate) ? (octal ? "0" : "0x") : "";
    const text = paddedNumber(spec, prefix, magnitude, "");
    return spec.conversion == 'X' ? asciiUppercase(text) : text;
}
