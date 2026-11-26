module flint.conc.wait_test;

import flint.arena : Error, Status;
import flint.conc : Deadline;
import flint.conc.wait : replaceWaitHook, waitUntil;

@safe:

private uint called;

private Error pretend(Deadline deadline) nothrow @nogc
{
    assert(deadline.monotonicNanoseconds != long.max);
    ++called;
    return Error(Status.cancelled);
}

unittest
{
    assert(waitUntil(Deadline.none()).code == Status.invalidArgument);
    const previous = replaceWaitHook(&pretend);
    assert(previous is null);
    scope (exit)
        if (replaceWaitHook(previous) !is &pretend)
            assert(0, "incorrect cooperative wait hook");
    called = 0;
    assert(waitUntil(Deadline.afterMillis(100)).code == Status.cancelled && called == 1);
    assert(waitUntil(Deadline.afterMillis(0)).code == Status.ok && called == 1);
}

@("without a hook, waitUntil sleeps the calling thread until the deadline has passed")
unittest
{
    const deadline = Deadline.afterMillis(5);
    assert(waitUntil(deadline).code == Status.ok);
    assert(Deadline.afterMillis(0).monotonicNanoseconds >= deadline.monotonicNanoseconds);
}
