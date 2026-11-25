module flint.os.sys.threads;

import core.gc.gcinterface : GC;
import core.thread.osthread : Thread;
import core.thread.types : ThreadID;
import flint.arena : Error, Result, Status;

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

/// What the interrupt coordinator thread runs. It crosses to the new thread in C memory, so no GC closure is ever
/// reachable only from a thread the collector does not scan.
package(flint.os) struct CoordinatorLaunch
{
    int descriptor;
    ulong epoch;
    void function(int, ulong) nothrow entry;
}

private struct LaunchBlock
{
    CoordinatorLaunch launch;

    // SAFETY: `this` is the block startLowLevel malloc'd for exactly this thread; it is copied and freed once,
    // before the entry runs, and nothing else holds it.
    void run() @trusted nothrow
    {
        import core.stdc.stdlib : free;

        const copy = launch;
        free(&this);
        copy.entry(copy.descriptor, copy.epoch);
    }
}

/// Start `launch` on a thread druntime does not register: a collection neither signals nor scans it. It must not
/// touch GC memory until `attachForCallbacks`.
// SAFETY: The delegate's context is a malloc'd LaunchBlock, owned by the new thread from here on (freed here only if
// no thread started); druntime copies the delegate before createLowLevelThread returns.
@trusted package(flint.os) Result!ThreadID startLowLevel(CoordinatorLaunch launch) nothrow @nogc
{
    import core.stdc.stdlib : free, malloc;
    import core.thread.osthread : createLowLevelThread;

    enum notStarted = Error(Status.resourceExhausted, "could not start the interrupt coordinator");
    auto block = cast(LaunchBlock*) malloc(LaunchBlock.sizeof);
    if (block is null)
        return Result!ThreadID(ThreadID.init, notStarted);
    block.launch = launch;
    const id = createLowLevelThread(&block.run);
    if (id == ThreadID.init)
    {
        free(block);
        return Result!ThreadID(ThreadID.init, notStarted);
    }
    return Result!ThreadID(id);
}

// SAFETY: Joins only a thread startLowLevel started, once, from the synchronous retiring caller.
@trusted package(flint.os) void joinLowLevel(ThreadID id) nothrow @nogc
{
    import core.thread.osthread : joinLowLevelThread;

    joinLowLevelThread(id);
}

/// A low-level thread that nobody will join releases its own resources as it ends.
// SAFETY: Detaches only the calling thread, which is about to return from its entry.
@trusted package(flint.os) void orphanLowLevel() nothrow @nogc
{
    version (Posix)
    {
        import core.sys.posix.pthread : pthread_detach, pthread_self;

        pthread_detach(pthread_self());
    }
}

/// Register the calling low-level thread with druntime and run its module thread-local constructors, so callbacks
/// may use the GC and thread-local state as on any D thread. Once only: druntime cannot attach a thread again after
/// `detachAfterCallbacks`.
// SAFETY: The calling thread is a running low-level thread not yet known to druntime; thread_attachThis registers it.
@trusted package(flint.os) void attachForCallbacks() nothrow
{
    import core.thread.osthread : thread_attachThis;

    try
    {
        thread_attachThis();
        rt_moduleTlsCtor();
    }
    catch (Exception)
        assert(0, "the interrupt coordinator could not join the D runtime");
}

/// Undo `attachForCallbacks` as the thread ends: thread-local destructors, the collector's per-thread state, then
/// druntime's registration.
// SAFETY: Called once on the attached coordinator, on its way out; it touches no GC memory afterwards.
@trusted package(flint.os) void detachAfterCallbacks() nothrow
{
    import core.thread.threadbase : thread_detachThis;

    try
        rt_moduleTlsDtor();
    catch (Exception)
    {
    }
    gc_getProxy().cleanupThread(Thread.getThis());
    thread_detachThis();
}

private extern (C) void rt_moduleTlsCtor();
private extern (C) void rt_moduleTlsDtor();
/// druntime's current collector (core.internal.gc.proxy).
private extern (C) GC gc_getProxy() nothrow @nogc;
