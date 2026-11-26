module app;

import flint.java.util.date : Date;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)((new Date(cast(long) arg.length)).toString().length) & 127;
}
