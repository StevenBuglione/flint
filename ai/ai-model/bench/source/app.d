module app;

import core.stdc.stdio : fputc, stdout;
import flint.ai.chat.messages.part : OpaquePayload;

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
    const payload = OpaquePayload(provider, kind, data);
    emit(payload.provider());
    emit(payload.kind());
    emit(payload.data());
    return 0;
}
