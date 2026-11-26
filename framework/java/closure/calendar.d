module app;

import flint.java.util.calendar : GregorianCalendar;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)((new GregorianCalendar(2000, 1, cast(int) arg.length)).getTimeInMillis()) & 127;
}
