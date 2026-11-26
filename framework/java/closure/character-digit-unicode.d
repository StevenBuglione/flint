module app;

import flint.java.lang.character : digit, isDigit;

@safe:

int main(string[] args)
{
    const int point = args.length > 1 ? 0x0667 : 0x1d7df;
    return isDigit(point) && digit(point, 10) == 7 ? 0 : 1;
}
