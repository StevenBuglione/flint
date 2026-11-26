module app;

import flint.java.util : Optional;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(Optional!string.of(arg).get().length) & 127;
}
