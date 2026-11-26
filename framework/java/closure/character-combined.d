module app;

import flint.java.lang.character : digit, isDigit, isWhitespace;

@safe:

int main(string[] args)
{
    const point = cast(int) args.length;
    const ascii = cast(char) point;
    const unit = cast(wchar)(0x660 + point);
    const scalar = 0x1D7CE + point;
    const radix = 9 + point;
    return (digit(ascii, radix) + digit(unit, radix) + digit(scalar, radix) + isDigit(ascii)
        + isDigit(unit) + isDigit(scalar) + isWhitespace(cast(dchar) point)) & 31;
}
