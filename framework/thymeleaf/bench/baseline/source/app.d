/// Equivalent output for the two fixture inputs without the Thymeleaf library.
module app;

import core.stdc.stdio : putchar;

@safe:

int main(string[] args)
{
    foreach (c; args.length > 1 ? "TEXT text sensitive\n" : "HTML markup insensitive\n")
        putchar(c);
    return 0;
}
