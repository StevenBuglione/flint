module app;

import flint.java.util.concurrent.atomic : AtomicInteger;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)((new AtomicInteger(cast(int) arg.length)).incrementAndGet()) & 127;
}
