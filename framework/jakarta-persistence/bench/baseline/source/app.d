module app;

import core.stdc.stdio : fputc, stdout;

@safe:

private void emit(scope const(char)[] text) nothrow @nogc
{
    foreach (c; text)
        fputc(c, stdout);
    fputc('\n', stdout);
}

int main(string[] args)
{
    emit(args.length > 1 ? "owners" : "Owner owners id");
    return 0;
}
