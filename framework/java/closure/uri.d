module app;

import flint.java.net : URI;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(URI.create(arg).isAbsolute()) & 127;
}
