/// Java SE 21 Unicode digit classification and radix digit conversion.
module flint.java.lang.character;

public import flint.java.lang.internal.characterwhitespace : isWhitespace;

import flint.java.lang.internal.asciidigits : asciiDigit = digit, isAsciiDigit = isDigit;
import flint.java.lang.internal.bmpdigits : bmpDigit = digit, isBmpDigit = isDigit;
import flint.java.lang.internal.unicodedigits : unicodeDigit = digit, isUnicodeDigit = isDigit;

@safe:

alias digit = asciiDigit;
alias digit = bmpDigit;
alias digit = unicodeDigit;

alias isDigit = isAsciiDigit;
alias isDigit = isBmpDigit;
alias isDigit = isUnicodeDigit;
