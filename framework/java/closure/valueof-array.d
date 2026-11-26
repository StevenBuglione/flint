module app;

import flint.java.lang : valueOf;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(valueOf([arg]).length) & 127;
}
