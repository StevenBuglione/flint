/// Thread-local cooperative waiting for native owner loops and blocking callers.
module flint.conc.wait;

import core.thread.osthread : Thread;
import core.time : nsecs;
import flint.arena : Error, Status;
import flint.conc : Deadline;

@safe:

/// A scheduler hook installed on its own OS thread.
alias WaitHook = Error function(Deadline deadline) @safe nothrow @nogc;

private WaitHook current;

/// Install a calling-thread scheduler hook and return the previous hook.
WaitHook replaceWaitHook(WaitHook hook) nothrow @nogc
{
    const previous = current;
    current = hook;
    return previous;
}

/// Cooperatively wait on an owner loop or sleep on an ordinary calling thread.
Error waitUntil(Deadline deadline) nothrow @nogc
{
    const target = deadline.monotonicNanoseconds;
    if (target == long.max)
        return Error(Status.invalidArgument, "cooperative wait requires a finite deadline");
    const now = Deadline.afterMillis(0).monotonicNanoseconds;
    if (target <= now)
        return Error.init;
    if (current !is null)
        return current(deadline);
    Thread.sleep((target - now).nsecs);
    return Error.init;
}
