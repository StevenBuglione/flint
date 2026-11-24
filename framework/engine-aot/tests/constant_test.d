/++
`statelessInstance` across threads: druntime's `Thread.start` is `@system`, so this check lives in a test module
without `@safe:`, as the other thread tests do.
+/
module flint.engine.aot.constant_test;

import flint.engine.aot.objects : statelessInstance;

private final class Shared
{
}

unittest
{
    import core.thread : Thread;

    // Another thread gets the very same object, not a thread-local copy, and synchronizing on it works.
    Shared seen;
    auto thread = new Thread({ seen = statelessInstance!Shared(); });
    thread.start();
    thread.join();
    assert(seen !is null && seen is statelessInstance!Shared());
    synchronized (seen)
    {
    }
}
