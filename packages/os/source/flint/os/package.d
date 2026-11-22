module flint.os;

import flint.arena : Error, Result;
import flint.conc : Context;
import flint.os.internal : execute;
import flint.os.globbing : searchGlob;
import flint.os.sys.interrupts : registerInterrupt, unregisterInterrupt;

public import flint.os.types : EnvVar, ExitStatus, GlobOptions, OutputSink, ProcessOptions;

@safe:

/// Execute literal argv and retain the combined bounded output until the returned arrays are released.
Result!ExitStatus run(ref scope Context context, scope const(char[])[] argv, ProcessOptions options = ProcessOptions
        .init)
{
    return execute(context, argv, null, null, options, true);
}

/// Execute literal argv and stream both pipes. Each borrowed chunk is valid during its callback.
Result!ExitStatus stream(ref scope Context context, scope const(char[])[] argv,
        scope OutputSink stdoutSink, scope OutputSink stderrSink, ProcessOptions options = ProcessOptions.init)
{
    return execute(context, argv, stdoutSink, stderrSink, options, false);
}

/// Find matching root-relative paths, sorted lexicographically.
Result!(string[]) glob(scope const(char)[] root, scope const(char)[] pattern, GlobOptions options = GlobOptions.init)
{
    return searchGlob(root, pattern, options);
}

/// An owned subscription to the process-wide interrupt coordinator.
struct InterruptSubscription
{
    private ulong id;

    @disable this(this);

    ~this() nothrow
    {
        close();
    }

    /// Remove the subscription and wait for any invocation already running on another thread.
    Error close() nothrow
    {
        if (id == 0)
            return Error.init;
        const removed = id;
        id = 0;
        return unregisterInterrupt(removed);
    }
}

/// Dispatch SIGINT callbacks on a coordinator thread. An existing custom handler keeps ownership.
Result!InterruptSubscription onInterrupt(void delegate() @safe callback)
{
    const registered = registerInterrupt(callback);
    if (!registered.ok)
        return Result!InterruptSubscription(InterruptSubscription.init, registered.error);
    return Result!InterruptSubscription(InterruptSubscription(registered.value));
}
