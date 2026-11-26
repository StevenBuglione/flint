module app;

import flint.java.lang.character : digit, isDigit;

@safe:

int main(string[] args)
{
    const wchar unit = args.length > 1 ? 0xff17 : 0x0667;
    return isDigit(unit) && digit(unit, 10) == 7 ? 0 : 1;
}
