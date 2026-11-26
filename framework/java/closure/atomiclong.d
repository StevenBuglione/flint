module app;

import flint.java.util.concurrent.atomic.atomiclong : AtomicLong;

@safe:

int main(string[] args)
{
    auto count = new AtomicLong(cast(long) args.length);
    count.addAndGet(1);
    return cast(int) count.toString().length;
}
