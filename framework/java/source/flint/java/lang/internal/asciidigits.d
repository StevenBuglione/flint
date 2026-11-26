/// Character digit operations for single UTF-8 code units.
module flint.java.lang.internal.asciidigits;

@safe:

bool isDigit(char codeUnit) pure nothrow @nogc
{
    return codeUnit >= '0' && codeUnit <= '9';
}

int digit(char codeUnit, int radix) pure nothrow @nogc
{
    if (radix < 2 || radix > 36)
        return -1;
    const lower = codeUnit | 0x20;
    const int value = isDigit(codeUnit) ? codeUnit - '0' : lower >= 'a' && lower <= 'z' ? lower - 'a' + 10 : -1;
    return value < radix ? value : -1;
}
