module app;

import flint.java.nio.charset : Charset;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "UTF-8";
    return cast(int)(Charset.forName(arg).name().length) & 127;
}
