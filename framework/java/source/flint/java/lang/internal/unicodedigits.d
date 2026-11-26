/// Character digit operations for Unicode code points.
module flint.java.lang.internal.unicodedigits;

import flint.java.lang.internal.bmpdigits : bmpDigit = digit, isBmpDigit = isDigit;
import flint.java.lang.internal.data.supplementarydigits : decimalStarts;

@safe:

bool isDigit(int codePoint) pure nothrow @nogc
{
    if (cast(uint) codePoint <= wchar.max)
        return isBmpDigit(cast(wchar) codePoint);
    return decimalDigit(cast(uint) codePoint) >= 0;
}

int digit(int codePoint, int radix) pure nothrow @nogc
{
    if (cast(uint) codePoint <= wchar.max)
        return bmpDigit(cast(wchar) codePoint, radix);
    if (radix < 2 || radix > 36)
        return -1;

    const int value = decimalDigit(cast(uint) codePoint);
    return value < radix ? value : -1;
}

private int decimalDigit(uint codePoint) pure nothrow @nogc
{
    size_t left;
    size_t right = decimalStarts.length;
    while (left < right)
    {
        const size_t middle = left + (right - left) / 2;
        const uint start = decimalStarts[middle];
        if (codePoint < start)
            right = middle;
        else if (codePoint > start + 9)
            left = middle + 1;
        else
            return cast(int)(codePoint - start);
    }
    return -1;
}
