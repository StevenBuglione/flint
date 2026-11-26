module flint.closure.decimaldigits;

import flint.java.lang.character.decimaldigits : javaDecimalDigit;

@safe:

int main(string[] args)
{
    const uint unit = args.length > 1 ? cast(uint) args[1].length : 0x0660;
    return cast(int)(javaDecimalDigit(unit) & 127);
}
