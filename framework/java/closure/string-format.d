module app;

import flint.java.lang : String;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(String.format("%s %s", arg, arg.length).length) & 127;
}
