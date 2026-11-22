module app;

import probe : check, printChecksum, runProbe;

@safe:

private int decimal(scope const(char)[] digits)
{
    uint number;
    foreach (ch; digits)
    {
        check(ch >= '0' && ch <= '9');
        number = number * 10 + cast(uint)(ch - '0');
    }
    return cast(int) number;
}

pragma(inline, false) private long reference(scope const(char)[] argument, size_t width)
{
    check(argument.length >= 14 && argument[0 .. 9] == "--option-" && argument[12] == '=');
    const index = decimal(argument[9 .. 12]);
    check(index >= 0 && cast(size_t) index < width);
    return decimal(argument[13 .. $]);
}

void main(string[] args)
{
    check(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const measure = args.length == 2;
    version (FlintCliScale)
    {
        printChecksum(10, runProbe(&reference, 10, measure));
        printChecksum(256, runProbe(&reference, 256, measure));
    }
    printChecksum(64, runProbe(&reference, 64, measure));
}
