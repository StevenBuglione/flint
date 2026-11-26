module app;

import flint.java.io : ByteArrayInputStream;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)((new ByteArrayInputStream(cast(const(ubyte)[]) arg)).read()) & 127;
}
