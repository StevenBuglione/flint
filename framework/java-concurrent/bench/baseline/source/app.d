module app;

import core.stdc.stdio : fputc, stdout;

@safe:

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    fputc('0' + count % 10, stdout);
    fputc('\n', stdout);
    return 0;
}
