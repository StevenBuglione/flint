module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.time.period : Period;

@safe:

int main(string[] args)
{
    const text = args.length > 1 ? args[1] : "P6Y3M1D";
    const period = Period.parse(text).plusMonths(10).normalized();
    foreach (c; period.toString())
        fputc(c, stdout);
    fputc('\n', stdout);
    return 0;
}
