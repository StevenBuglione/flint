module app;

import flint.java.character : isLetter;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(isLetter(arg[0])) & 127;
}
