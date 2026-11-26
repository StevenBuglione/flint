module app;

import flint.java.object : Any;

@safe:

int main(string[] args)
{
    const value = args.length > 1 ? Any.of(args[1]) : Any.of(cast(long) args.length);
    if (value.holds!string)
        return cast(int) value.get!string.length & 127;
    return cast(int) value.get!long & 127;
}
