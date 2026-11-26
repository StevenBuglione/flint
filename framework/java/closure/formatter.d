module app;

import flint.java.util.formatter : formatJava;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(formatJava(arg, []).length) & 127;
}
