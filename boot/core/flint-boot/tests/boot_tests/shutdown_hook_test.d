/// Flint tests: `FlintApplication.runMain`'s shutdown hook turns SIGTERM into a close request (Boot's
/// SpringApplicationShutdownHook; ADR-028's graceful SIGTERM and SIGINT in Flint Boot).
module boot_tests.shutdown_hook_test;

import flint.boot : KeepAliveApplicationContext, ShutdownHook;

/// A keep-alive context that never terminates by itself.
private final class Forever : KeepAliveApplicationContext
{
    void awaitTermination() @safe
    {
    }

    bool isTerminated() @safe
    {
        return false;
    }
}

version (Posix) @("aSigtermRequestsShutdownAndEndsTheWait") @safe unittest
{
    import core.thread.osthread : Thread;
    import core.time : msecs;
    import std.conv : to;
    import std.process : execute, thisProcessID;

    auto hook = new ShutdownHook;
    hook.install();
    scope (exit)
        hook.uninstall();
    // Only raise the signal while the hook handles it; otherwise SIGTERM's default action would end the run.
    if (!hook.isInstalled())
        return;
    assert(!hook.isShutdownRequested());
    const sent = execute(["kill", "-TERM", thisProcessID.to!string]);
    assert(sent.status == 0, sent.output);
    foreach (_; 0 .. 100)
    {
        if (hook.isShutdownRequested())
            break;
        Thread.sleep(20.msecs);
    }
    assert(hook.isShutdownRequested());
    assert(hook.getSignalCount() == 1);
    hook.await(new Forever); // returns at once: a shutdown was requested
}

@("noSignalNoRequest") @safe unittest
{
    auto hook = new ShutdownHook;
    assert(!hook.isShutdownRequested() && hook.getSignalCount() == 0);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
