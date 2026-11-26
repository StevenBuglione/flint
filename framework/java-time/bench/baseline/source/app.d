module app;

import core.stdc.stdio : fputc, stdout;

@safe:

int main(string[] args)
{
    foreach (c; args.length > 1 ? "P1Y3D\n" : "P7Y1M1D\n")
        fputc(c, stdout);
    return 0;
}
