module character_digit_tests;

import flint.java.lang.character : digit, isDigit;

@safe:

@("Java radix digits include Unicode decimal digits and fullwidth Latin letters") unittest
{
    assert(digit(cast(char) '9', 10) == 9);
    assert(digit(cast(char) 'F', 16) == 15);
    assert(digit(cast(char) 'F', 15) == -1);
    assert(digit(cast(wchar) 0x0667, 10) == 7);
    assert(digit(cast(wchar) 0xff26, 16) == 15);
    assert(digit(0x1d7df, 10) == 7);
    assert(digit(0x1d7df, 7) == -1);
    assert(digit(0xff46, 16) == 15);
    assert(digit(-1, 10) == -1);
    assert(digit(0x11_0000, 36) == -1);
    assert(digit(cast(wchar) 0xd800, 16) == -1);
    assert(digit(cast(char) '0', 1) == -1);
    assert(digit(cast(char) '0', 37) == -1);
}

@("Java isDigit tests the decimal number category") unittest
{
    assert(isDigit(cast(char) '0'));
    assert(!isDigit(cast(char) 'A'));
    assert(!isDigit(cast(char) 0xb2));
    assert(isDigit(cast(wchar) 0x0667));
    assert(isDigit(0x1d7df));
    assert(isDigit(cast(dchar) 0x1d7df));
    assert(!isDigit(0x2163));
    assert(!isDigit(0x00b2));
    assert(!isDigit(0xff26));
    assert(!isDigit(-1));
    assert(!isDigit(0x11_0000));
}
