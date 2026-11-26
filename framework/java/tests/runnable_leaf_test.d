module flint.java.runnable_leaf_test;

import flint.java.lang : LegacyRunnable = Runnable;
import flint.java.lang.runnable : Runnable;

@safe:

private final class Task : Runnable
{
    int calls;

    override void run() nothrow @nogc
    {
        ++calls;
    }
}

unittest
{
    static assert(is(LegacyRunnable == Runnable));
    auto task = new Task();
    LegacyRunnable legacy = task;
    Runnable direct = legacy;
    direct.run();
    legacy.run();
    assert(task.calls == 2);
}
