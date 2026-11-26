module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent : TimeUnit;

@safe:

pragma(inline, false) private bool exercise(long time, TimeUnit unit) pure nothrow @nogc
{
    return time > 0 && unit == TimeUnit.NANOSECONDS;
}

int main(string[] args)
{
    fputc(exercise(cast(long) args.length - 1, TimeUnit.NANOSECONDS) ? '1' : '0', stdout);
    fputc('\n', stdout);
    return 0;
}
