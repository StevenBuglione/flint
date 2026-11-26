module app;

import flint.java.classref : ClassRef;

@safe:

int main(string[] args)
{
    const value = ClassRef(args.length > 1 ? args[1] : null);
    return cast(int) value.toString().length & 127;
}
