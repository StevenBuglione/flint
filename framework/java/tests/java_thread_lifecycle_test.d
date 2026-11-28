// Flint conformance cases for Thread.start, join, sleep and the uncaught-exception handler.
module flint.java.lang.thread_lifecycle_test;

import core.atomic : atomicLoad, atomicStore;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.lang.interruptedexception : InterruptedException;
import flint.java.lang.runnable : Runnable;
import flint.java.lang.thread : Thread;

@safe:

private final class ThrowingRunnable : Runnable
{
    private Throwable error;

    this(Throwable error)
    {
        this.error = error;
    }

    void run() @safe
    {
        throw error;
    }
}

@("start runs the task on its own thread, which currentThread identifies") unittest
{
    auto body = new class Runnable
    {
        Thread expected;
        shared bool same;

        void run() @safe
        {
            atomicStore(same, Thread.currentThread() is expected);
        }
    };
    auto t = new Thread(body, "lifecycle-worker");
    body.expected = t;

    assert(t.getState() == Thread.State.NEW);
    assert(!t.isAlive());
    t.start();
    t.join();

    assert(atomicLoad(body.same), "the started thread saw another Thread object");
    assert(t.getState() == Thread.State.TERMINATED);
    assert(!t.isAlive());
    assert(t.getName() == "lifecycle-worker");
}

@("a second start, and a start after termination, throw IllegalStateException") unittest
{
    auto t = new Thread(new class Runnable
        {
        void run() @safe
        {
        }
    }
);
    t.start();
    t.join();

    foreach (attempt; 0 .. 2)
    {
        bool threw;
        try
            t.start();
        catch (IllegalStateException)
            threw = true;
        assert(threw);
    }
}

@("interrupting a sleeping thread throws InterruptedException and clears the flag") unittest
{
    auto body = new class Runnable
    {
        shared bool ready;
        shared bool caught;
        shared bool cleared;

        void run() @safe
        {
            atomicStore(ready, true);
            try
                Thread.sleep(10_000);
            catch (InterruptedException)
            {
                atomicStore(caught, true);
                atomicStore(cleared, !Thread.currentThread().isInterrupted());
            }
        }
    };
    auto t = new Thread(body);
    t.start();
    while (!atomicLoad(body.ready))
    {
    }
    t.interrupt();
    t.join();

    assert(atomicLoad(body.caught), "sleep did not throw InterruptedException");
    assert(atomicLoad(body.cleared), "sleep left the interrupt flag set");
}

@("interrupting a joining thread throws InterruptedException and clears the flag") unittest
{
    auto body = new class Runnable
    {
        shared bool ready;
        shared bool done;

        void run() @safe
        {
            atomicStore(ready, true);
            while (!atomicLoad(done))
                Thread.sleep(1);
        }
    };
    auto target = new Thread(body);
    target.start();
    while (!atomicLoad(body.ready))
    {
    }

    auto self = Thread.currentThread();
    self.interrupt();
    bool threw;
    try
        target.join();
    catch (InterruptedException)
        threw = true;
    assert(threw, "join did not throw InterruptedException");
    assert(!self.isInterrupted(), "join left the interrupt flag set");

    atomicStore(body.done, true);
    target.join();
}

@("a timed join returns while the target is still running") unittest
{
    auto body = new class Runnable
    {
        shared bool ready;
        shared bool done;

        void run() @safe
        {
            atomicStore(ready, true);
            while (!atomicLoad(done))
                Thread.sleep(1);
        }
    };
    auto target = new Thread(body);
    target.start();
    while (!atomicLoad(body.ready))
    {
    }

    target.join(20);
    assert(target.isAlive(), "the timed join waited for termination");

    atomicStore(body.done, true);
    target.join();
    assert(!target.isAlive());
}

@("an uncaught exception reaches the thread's handler and is kept on the thread") unittest
{
    auto handler = new class Thread.UncaughtExceptionHandler
    {
        Thread thread;
        Throwable error;

        void uncaughtException(Thread thread, Throwable error) @safe
        {
            this.thread = thread;
            this.error = error;
        }
    };
    auto failure = new RuntimeException("boom");
    auto t = new Thread(new ThrowingRunnable(failure));
    t.setUncaughtExceptionHandler(handler);
    t.start();
    t.join();

    assert(handler.error is failure, "the handler did not receive the thrown exception");
    assert(handler.thread is t);
    assert(t.uncaughtError() is failure);
    assert(t.getState() == Thread.State.TERMINATED);
}

@("sleep rejects a negative duration and an out-of-range nanosecond part") unittest
{
    bool negative;
    try
        Thread.sleep(-1);
    catch (IllegalArgumentException)
        negative = true;
    assert(negative);

    bool nanos;
    try
        Thread.sleep(0, 1_000_000);
    catch (IllegalArgumentException)
        nanos = true;
    assert(nanos);

    Thread.sleep(0);
}
