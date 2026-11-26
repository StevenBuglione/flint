module app;

import flint.java.lang : Double;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(Double.toString(arg.length + 0.5).length) & 127;
}
