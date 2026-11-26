module app;

import flint.java.util.timezone : TimeZone;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(TimeZone.getTimeZone(arg).getRawOffset()) & 127;
}
