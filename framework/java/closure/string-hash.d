module app;

import flint.java.lang : javaHashCode;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(javaHashCode(arg)) & 127;
}
