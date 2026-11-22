module flint.os.sys.threads;

import core.thread.osthread : Thread;

@safe:

// SAFETY: This fresh druntime thread receives a retained, safe, nonthrowing entry delegate.
@trusted package(flint.os) Thread startThread(void delegate() @safe nothrow entry)
{
    return new Thread(entry).start();
}

// SAFETY: The synchronous caller joins only the druntime thread it launched.
@trusted package(flint.os) Throwable joinThread(Thread thread) nothrow
{
    try
        return thread.join(false);
    catch (Exception failure)
        return failure;
}
