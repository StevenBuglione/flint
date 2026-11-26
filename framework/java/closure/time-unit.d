module app;

import flint.java.util.concurrent : TimeUnit, toNanos;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(TimeUnit.MILLISECONDS.toNanos(arg.length)) & 127;
}
