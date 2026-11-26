module app;

import flint.java.lang : Integer;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "10";
    return cast(int)(Integer.parseInt(arg)) & 127;
}
