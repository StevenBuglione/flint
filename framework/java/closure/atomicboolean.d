module app;

import flint.java.util.concurrent.atomic.atomicboolean : AtomicBoolean;

@safe:

int main(string[] args)
{
    auto flag = new AtomicBoolean(args.length > 1);
    flag.compareAndExchangeRelease(false, true);
    return flag.getAcquire() ? 1 : 0;
}
