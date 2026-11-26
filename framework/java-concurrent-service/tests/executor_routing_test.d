module flint.java.util.concurrent.executor_routing_test;

import core.memory : GC;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.internal.executoradmissions : Admission, ExecutorAdmissions, ExecutorClaim;
import flint.java.util.concurrent.internal.executorrouting : ExecutorRoutes;

@safe:

private final class Command : Runnable
{
    uint tag;

    this(uint tag)
    {
        this.tag = tag;
    }

    override void run()
    {
        ++tag;
    }
}

@("failed post returns the route and queue capacity without reusing the generation")
unittest
{
    auto routes = new ExecutorRoutes(1);
    auto queue = new ExecutorAdmissions(1);
    auto task = new Command(41);
    ulong failed;
    assert(routes.admit(queue, task, (ulong token) { failed = token; return false; }) == Admission.unavailable);
    assert(failed != 0);

    ulong accepted;
    assert(routes.admit(queue, task, (ulong token) { accepted = token; return true; }) == Admission.accepted);
    assert(accepted != 0 && accepted != failed);
    auto other = new ExecutorAdmissions(1);
    bool called;
    assert(routes.admit(other, task, (ulong token) { called = true; return true; }) == Admission.unavailable);
    assert(!called);
    ExecutorClaim claim;
    assert(routes.takePermit(failed) is null);
    assert(routes.takePermit(0) is null);
    assert(routes.takePermit(ulong.max) is null);
    assert(routes.takePermit(accepted) is queue && queue.tryStart(claim) && claim.command is task);
    queue.retire(claim);
}

@("a duplicate scalar cannot take the next pending command")
unittest
{
    auto routes = new ExecutorRoutes(2);
    auto queue = new ExecutorAdmissions(2);
    auto first = new Command(11);
    auto second = new Command(22);
    ulong[2] tokens;
    assert(routes.admit(queue, first, (ulong token) { tokens[0] = token; return true; }) == Admission.accepted);
    assert(routes.admit(queue, second, (ulong token) { tokens[1] = token; return true; }) == Admission.accepted);

    ExecutorClaim claim;
    assert(routes.takePermit(tokens[0]) is queue && queue.tryStart(claim) && claim.command is first);
    queue.retire(claim);
    assert(routes.takePermit(tokens[0]) is null);
    assert(routes.takePermit(tokens[1]) is queue && queue.tryStart(claim) && claim.command is second);
    queue.retire(claim);
}

@("immediate shutdown returns FIFO identities and immediately releases their routes")
unittest
{
    auto routes = new ExecutorRoutes(2);
    auto oldQueue = new ExecutorAdmissions(2);
    auto first = new Command(11);
    auto second = new Command(22);
    ulong[2] stale;
    assert(routes.admit(oldQueue, first, (ulong token) { stale[0] = token; return true; }) == Admission.accepted);
    assert(routes.admit(oldQueue, second, (ulong token) { stale[1] = token; return true; }) == Admission.accepted);

    auto returned = routes.shutdownNow(oldQueue);
    assert(returned.length == 2 && returned[0] is first && returned[1] is second);
    assert(oldQueue.isTerminated());

    auto newQueue = new ExecutorAdmissions(1);
    auto next = new Command(33);
    ulong current;
    assert(routes.admit(newQueue, next, (ulong token) { current = token; return true; }) == Admission.accepted);
    ExecutorClaim claim;
    assert(routes.takePermit(stale[0]) is null);
    assert(routes.takePermit(stale[1]) is null);
    assert(routes.takePermit(current) is newQueue && newQueue.tryStart(claim) && claim.command is next);
    newQueue.retire(claim);
}

private ulong publishTemporaryService(ExecutorRoutes routes)
{
    auto queue = new ExecutorAdmissions(1);
    auto task = new Command(123);
    ulong scalar;
    assert(routes.admit(queue, task, (ulong token) { scalar = token; return true; }) == Admission.accepted);
    return scalar;
}

@("the route keeps the pending queue and command alive across a collection")
unittest
{
    auto routes = new ExecutorRoutes(1);
    const scalar = publishTemporaryService(routes);
    GC.collect();
    ExecutorClaim claim;
    auto queue = routes.takePermit(scalar);
    assert(queue !is null && queue.tryStart(claim));
    auto task = cast(Command) claim.command;
    assert(task !is null && task.tag == 123);
    queue.retire(claim);
}
