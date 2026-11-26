module app;

import core.stdc.stdio : fputc, stdout;
import flint.util : Assert;

@safe:

private void emit(scope const(char)[] text) nothrow @nogc
{
    foreach (c; text)
        fputc(c, stdout);
    fputc('\n', stdout);
}

int main(string[] args)
{
    const provider = args.length > 1 ? args[1] : "anthropic";
    const kind = args.length > 2 ? args[2] : "signature";
    const data = args.length > 3 ? args[3] : "c2lnbmF0dXJl";
    Assert.hasText(provider, "provider must not be empty");
    Assert.hasText(kind, "kind must not be empty");
    Assert.notNull(data, "data must not be null");
    emit(provider);
    emit(kind);
    emit(data);
    return 0;
}
