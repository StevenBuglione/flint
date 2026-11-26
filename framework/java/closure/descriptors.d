module app;

import flint.java.util.descriptors : rawListDescriptor;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(rawListDescriptor(arg, "int").name.length) & 127;
}
