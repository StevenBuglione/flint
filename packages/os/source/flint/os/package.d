module flint.os;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.lifetime : move;
import flint.arena : Error, Result, Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.os.internal : execute;
import flint.os.globbing : searchGlob;
import flint.os.sys.interrupts : registerInterrupt, unregisterInterrupt;

public import flint.os.types : EnvVar, ExitStatus, GlobOptions, OutputSink, ProcessOptions, ShutdownSignal;

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
    if (callback is null)
        return Result!InterruptSubscription(InterruptSubscription.init,
                Error(Status.invalidArgument, "interrupt callback required"));
    return subscribe((ShutdownSignal) @safe { callback(); }, 1U << ShutdownSignal.interrupt);
}

/// Dispatch SIGTERM and SIGINT callbacks on a coordinator thread, once per signal received. On Windows these are
/// Ctrl+Break and Ctrl+C. A signal that already has a custom handler keeps it, and the subscription fails.
Result!InterruptSubscription onShutdownSignal(void delegate(ShutdownSignal) @safe callback)
{
    return subscribe(callback, 1U << ShutdownSignal.interrupt | 1U << ShutdownSignal.terminate);
}

private Result!InterruptSubscription subscribe(void delegate(ShutdownSignal) @safe callback, uint signals)
{
    const registered = registerInterrupt(callback, signals);
    if (!registered.ok)
        return Result!InterruptSubscription(InterruptSubscription.init, registered.error);
    return Result!InterruptSubscription(InterruptSubscription(registered.value));
}

/// SIGTERM and SIGINT as cancellation, after Spring Boot's graceful shutdown: the first signal cancels `graceful`,
/// which asks the application to drain, and a second signal cancels `forced`, which asks it to stop now.
/// Pass both to `flint.web.serve`. Closing the watch restores the signals' previous dispositions.
struct ShutdownSignals
{
    private SignalLatch* latch;
    private InterruptSubscription subscription;

    @disable this(this);

    ~this() nothrow
    {
        close();
    }

    /// Cancelled by the first SIGTERM or SIGINT.
    Context graceful() const nothrow @nogc
    {
        return latch is null ? Context.init : latch.graceful.context();
    }

    /// Cancelled by the second SIGTERM or SIGINT.
    Context forced() const nothrow @nogc
    {
        return latch is null ? Context.init : latch.forced.context();
    }

    /// Signals received so far.
    uint received() const nothrow @nogc
    {
        return latch is null ? 0 : atomicLoad(latch.count);
    }

    /// The first signal received; meaningful once `received` is nonzero.
    ShutdownSignal first() const nothrow @nogc
    {
        return latch is null ? ShutdownSignal.interrupt : cast(ShutdownSignal) atomicLoad(latch.first);
    }

    /// Stop watching and restore the previous dispositions. Contexts already taken keep their state.
    Error close() nothrow
    {
        if (latch is null)
            return Error.init;
        const closed = subscription.close();
        latch.graceful.close();
        latch.forced.close();
        latch = null;
        return closed;
    }
}

private struct SignalLatch
{
    CancelSource graceful;
    CancelSource forced;
    shared uint count;
    shared ubyte first;

    void receive(ShutdownSignal signal) @safe nothrow @nogc
    {
        const seen = atomicOp!"+="(count, 1U);
        if (seen == 1)
        {
            atomicStore(first, cast(ubyte) signal);
            graceful.cancel();
        }
        else
            forced.cancel();
    }
}

/// Watch SIGTERM and SIGINT as graceful and forced cancellation. It fails when either signal has a custom handler.
Result!ShutdownSignals watchShutdownSignals()
{
    auto latch = new SignalLatch;
    auto graceful = CancelSource.create(Context.init, Deadline.none());
    if (!graceful.ok())
        return Result!ShutdownSignals(ShutdownSignals.init, graceful.error);
    auto forced = CancelSource.create(Context.init, Deadline.none());
    if (!forced.ok())
    {
        graceful.value.close();
        return Result!ShutdownSignals(ShutdownSignals.init, forced.error);
    }
    move(graceful.value, latch.graceful);
    move(forced.value, latch.forced);
    auto subscribed = onShutdownSignal(&latch.receive);
    if (!subscribed.ok)
    {
        latch.graceful.close();
        latch.forced.close();
        return Result!ShutdownSignals(ShutdownSignals.init, subscribed.error);
    }
    Result!ShutdownSignals result;
    result.value.latch = latch;
    move(subscribed.value, result.value.subscription);
    return move(result);
}
