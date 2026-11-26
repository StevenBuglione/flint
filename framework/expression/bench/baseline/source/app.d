/// Control for the SpEL size probe.
module app;

import core.stdc.stdio : putchar;

@safe:

int main(string[] args)
{
    const value = args.length > 1 ? "Flint's expression" : "Spring's expression";
    foreach (c; value)
        putchar(c);
    putchar('\n');
    return 0;
}
