module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.time.period : Period;

@safe:

int main(string[] args)
{
    const offset = args.length > 1 ? "P2M3D" : "P6Y3M1D";
    const period = Period.parse(offset).plusMonths(10).normalized();
    foreach (c; period.toString())
        fputc(c, stdout);
    fputc('\n', stdout);
    return 0;
}
