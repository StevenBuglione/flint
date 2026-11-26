module flint.java.util.concurrent.executor_admissions_test;

import core.atomic : atomicLoad, atomicStore;
import core.thread : Thread;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.internal.executoradmissions : Admission, ExecutorAdmissions, ExecutorClaim;

@safe:

private final class Command : Runnable
{
    size_t executions;

    override void run()
    {
        ++executions;
    }
}

private Admission admit(ExecutorAdmissions queue, Runnable command) nothrow @nogc
{
    return queue.tryAdmit(command, () => true);
}

static assert(!__traits(compiles, { ExecutorClaim original; ExecutorClaim copied = original; }));

@("immediate shutdown returns pending identities in FIFO order and waits for active retirement")
unittest
{
    auto queue = new ExecutorAdmissions(2);
    auto running = new Command;
    auto first = new Command;
    auto second = new Command;
    ExecutorClaim active;
    assert(admit(queue, running) == Admission.accepted);
    assert(queue.tryStart(active) && active.command is running);
    assert(admit(queue, first) == Admission.accepted);
    assert(admit(queue, second) == Admission.accepted);
    assert(admit(queue, running) == Admission.full);

    const pending = queue.shutdownNow();
    assert(pending.length == 2 && pending[0] is first && pending[1] is second);
    assert(queue.isShutdown() && !queue.isTerminated());
    assert(admit(queue, running) == Admission.closed);
    assert(queue.shutdownNow().length == 0);
    ExecutorClaim afterStop;
    assert(!queue.tryStart(afterStop));
    queue.retire(active);
    assert(active.command is null && queue.isTerminated());
    assert(first.executions == 0 && second.executions == 0);
}

@("failed publication consumes no slot and orderly shutdown still drains accepted work")
unittest
{
    auto queue = new ExecutorAdmissions(1);
    auto command = new Command;
    size_t publications;
    auto tryPublish = () @safe nothrow @nogc { ++publications; return false; };
    assert(queue.tryAdmit(null, tryPublish) == Admission.invalidCommand && publications == 0);
    assert(queue.tryAdmit(command, tryPublish) == Admission.unavailable && publications == 1);
    assert(admit(queue, command) == Admission.accepted);
    assert(queue.tryAdmit(command, tryPublish) == Admission.full && publications == 1);
    queue.shutdown();
    assert(queue.isShutdown() && !queue.isTerminated());
    assert(queue.tryAdmit(command, tryPublish) == Admission.closed && publications == 1);
    ExecutorClaim active;
    assert(queue.tryStart(active) && active.command is command);
    assert(!queue.isTerminated());
    active.command.run();
    queue.retire(active);
    assert(queue.isTerminated() && command.executions == 1);
    assert(queue.shutdownNow().length == 0);
}

@("an empty executor terminates at shutdown")
unittest
{
    auto queue = new ExecutorAdmissions(1);
    assert(!queue.isShutdown() && !queue.isTerminated());
    queue.shutdown();
    assert(queue.isShutdown() && queue.isTerminated());
}

@("physical claims and immediate shutdown assign each queued command once")
@system unittest
{
    foreach (attempt; 0 .. 96)
    {
        auto queue = new ExecutorAdmissions(1);
        auto command = new Command;
        assert(admit(queue, command) == Admission.accepted);
        shared bool start;
        shared bool claimDecided;
        shared bool mayRetire;
        ExecutorClaim active;
        auto worker = new Thread({
            while (!atomicLoad(start))
                Thread.yield();
            if (queue.tryStart(active))
                assert(active.command is command);
            atomicStore(claimDecided, true);
            if (active.command !is null)
            {
                while (!atomicLoad(mayRetire))
                    Thread.yield();
                queue.retire(active);
            }
        }).start();

        atomicStore(start, true);
        const pending = queue.shutdownNow();
        while (!atomicLoad(claimDecided))
            Thread.yield();
        assert(pending.length <= 1);
        if (pending.length == 1)
            assert(pending[0] is command && active.command is null && queue.isTerminated());
        else
            assert(active.command is command && !queue.isTerminated());
        atomicStore(mayRetire, true);
        worker.join();
        assert(queue.isTerminated());
    }
}

private final class ThrowingCommand : Runnable
{
    override void run()
    {
        throw new Exception("task failure");
    }
}

@("a command failure retires outside the guard and permits the next claim")
unittest
{
    auto queue = new ExecutorAdmissions(2);
    auto failure = new ThrowingCommand;
    auto next = new Command;
    assert(admit(queue, failure) == Admission.accepted);
    assert(admit(queue, next) == Admission.accepted);
    queue.shutdown();
    {
        ExecutorClaim active;
        assert(queue.tryStart(active) && active.command is failure);
        scope (exit)
            queue.retire(active);
        bool sawFailure;
        try
            active.command.run();
        catch (Exception outcome)
            sawFailure = outcome.msg == "task failure";
        assert(sawFailure && !queue.isTerminated());
    }

    ExecutorClaim active;
    assert(queue.tryStart(active) && active.command is next);
    active.command.run();
    queue.retire(active);
    assert(next.executions == 1 && queue.isTerminated());
}
