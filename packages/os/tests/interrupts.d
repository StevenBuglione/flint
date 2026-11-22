module flint.os.interrupt_test;

import core.atomic : atomicLoad, atomicOp;
import core.sys.posix.signal : SIGINT, SIG_IGN, kill, sigaction, sigaction_t, sigemptyset;
import core.sys.posix.unistd : getpid;
import core.thread : Thread;
import core.time : msecs;
import flint.arena : Status;
import flint.os : onInterrupt;

private shared uint first;
private shared uint second;

private extern (C) void foreignAction(int number) nothrow @nogc
{
    if (number == SIGINT)
        atomicOp!"+="(first, 100U);
}

private void waitUntil(ref shared uint counter, uint value)
{
    foreach (_; 0 .. 1000)
    {
        if (atomicLoad(counter) >= value)
            return;
        Thread.sleep(1.msecs);
    }
    assert(0, "signal callback did not execute");
}

@("SIGINT is dispatched to multiple safe subscriptions and the previous ignored action returns")
unittest
{
    const caller = Thread.getThis();
    sigaction_t ignored, before;
    sigemptyset(&ignored.sa_mask);
    ignored.sa_handler = SIG_IGN;
    assert(sigaction(SIGINT, &ignored, &before) == 0);
    scope (exit)
        sigaction(SIGINT, &before, null);

    auto one = onInterrupt(() @safe { assert(Thread.getThis() !is caller); atomicOp!"+="(first, 1U); });
    assert(one.ok, one.error.message);
    auto two = onInterrupt(() @safe { atomicOp!"+="(second, 1U); });
    assert(two.ok, two.error.message);

    assert(kill(getpid(), SIGINT) == 0);
    waitUntil(first, 1);
    waitUntil(second, 1);
    assert(one.value.close().code == Status.ok);
    assert(kill(getpid(), SIGINT) == 0);
    waitUntil(second, 2);
    assert(atomicLoad(first) == 1);
    assert(two.value.close().code == Status.ok);

    sigaction_t restored;
    assert(sigaction(SIGINT, null, &restored) == 0);
    assert(restored.sa_handler == SIG_IGN);
    assert(kill(getpid(), SIGINT) == 0);
    assert(atomicLoad(second) == 2);
}

@("a different live SIGINT handler keeps ownership")
unittest
{
    sigaction_t foreign, before;
    sigemptyset(&foreign.sa_mask);
    foreign.sa_handler = &foreignAction;
    assert(sigaction(SIGINT, &foreign, &before) == 0);
    scope (exit)
        sigaction(SIGINT, &before, null);
    const subscription = onInterrupt(() @safe {});
    assert(subscription.error.code == Status.conflict);
    sigaction_t active;
    assert(sigaction(SIGINT, null, &active) == 0);
    assert(active.sa_handler == &foreignAction);
}
