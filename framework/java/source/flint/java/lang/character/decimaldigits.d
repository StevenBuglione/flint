/// Decimal digits for Java APIs that parse one UTF-16 code unit at a time.
module flint.java.lang.character.decimaldigits;

@safe:

/// Returns the decimal value of one UTF-16 code unit, or `uint.max`.
/// The BMP table matches Character.digit(char, 10) in the pinned JDK 21.0.13.1.
package(flint) uint javaDecimalDigit(uint unit) pure nothrow @nogc
{
    static immutable ushort[] decimalZeros = [
        0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6,
        0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0,
        0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0,
        0xAA50, 0xABF0, 0xFF10
    ];
    if (unit - '0' <= 9)
        return unit - '0';
    if (unit >= 0x80 && unit <= 0xFFFF)
        foreach (zero; decimalZeros)
            if (unit - zero <= 9)
                return unit - zero;
    return uint.max;
}
