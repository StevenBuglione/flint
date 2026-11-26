/// Character digit operations for Java UTF-16 code units.
module flint.java.lang.internal.bmpdigits;

import flint.java.lang.character.decimaldigits : javaDecimalDigit;
import flint.java.lang.internal.asciidigits : asciiDigit = digit;

@safe:

bool isDigit(wchar codeUnit) pure nothrow @nogc
{
    return javaDecimalDigit(codeUnit) != uint.max;
}

int digit(wchar codeUnit, int radix) pure nothrow @nogc
{
    if (codeUnit < 0x80)
        return asciiDigit(cast(char) codeUnit, radix);
    if (radix < 2 || radix > 36)
        return -1;

    // The fullwidth ASCII forms are offset by U+FEE0. Case-fold after subtracting it.
    const uint letter = ((cast(uint) codeUnit - 0xfee0) | 0x20U) - 'a';
    const uint value = letter < 26 ? letter + 10 : javaDecimalDigit(codeUnit);
    return value < cast(uint) radix ? cast(int) value : -1;
}
