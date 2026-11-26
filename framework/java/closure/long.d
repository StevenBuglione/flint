module app;

import flint.java.lang : Long;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "10";
    return cast(int)(Long.parseLong(arg)) & 127;
}
