module app;

import flint.java.lang.boolean : Boolean;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "true";
    return cast(int)(Boolean.parseBoolean(arg)) & 127;
}
