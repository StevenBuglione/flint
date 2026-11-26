module app;

import flint.java.character : toLowerCase;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(toLowerCase(arg[0])) & 127;
}
