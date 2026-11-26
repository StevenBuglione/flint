module app;

import flint.java.lang.character : digit, isDigit;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 && args[1].length ? args[1] : "7";
    const char unit = arg[0];
    return isDigit(unit) && digit(unit, 10) == 7 ? 0 : 1;
}
