module app;

import flint.java.character : toLowerCase;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(toLowerCase(cast(dchar)(arg[0] & 127))) & 127;
}
