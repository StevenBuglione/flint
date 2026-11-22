module flint.conc.sys.background;

import core.atomic : atomicLoad, atomicStore, cas;
import core.thread : Thread;
import flint.arena : Error, Status;

@safe:

/// A started background worker thread. Its owner tells the worker to stop through its own protocol,
/// waits for the worker's completion signal, and then calls `join`, so the thread has finished
/// druntime's per-thread teardown before the owner is released or the process exits.
package(flint) struct Background
{
    private Thread thread;
    private shared bool joined;

    /// Wait until the worker thread has exited. Idempotent and safe to race; call only after the
    /// worker has returned or been told to return, and never from the worker itself.
    void join() @trusted nothrow @nogc
    {
        if (thread is null || !cas(&joined, false, true))
            return;
        // SAFETY: `joinThread` allocates only on its failure path, which ends in assert(0); the cast
        // adds @nogc to a call that performs no GC allocation when it returns.
        (cast(void function(Thread) nothrow @nogc)&joinThread)(thread);
    }
}

// SAFETY: pthread_join fails only for a thread that was never started, already joined or detached.
// The thread is started before `Background` holds it, `joined` admits one caller, and the handle
// keeps the Thread reachable so its finalizer cannot detach it first.
private @trusted void joinThread(Thread thread) nothrow
{
    try
        thread.join(false);
    catch (Exception)
        assert(0, "background worker thread could not be joined");
}

// SAFETY: Druntime retains this owned safe entry for the thread's lifetime. The worker's
// shutdown protocol publishes completion before its owner joins the thread.
@trusted package(flint.conc) Error startDaemon(void delegate() @safe nothrow run, out Background worker)
{
    if (run is null)
        return Error(Status.invalidArgument, "missing background entry");
    try
    {
        auto entered = new shared(bool);
        auto thread = new Thread({ atomicStore(*entered, true); run(); });
        thread.isDaemon = true;
        thread.start();
        // The entry runs after druntime registers the thread and runs its thread-local module
        // constructors. Waiting for it means no worker is still inside that start-up when its owner
        // continues, which could otherwise overlap runtime termination at process exit.
        while (!atomicLoad(*entered))
            Thread.yield();
        worker.thread = thread;
        return Error.init;
    }
    catch (Exception)
    {
        return Error(Status.unavailable, "could not start background worker");
    }
}
