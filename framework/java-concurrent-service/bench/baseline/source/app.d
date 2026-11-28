module flint.java.util.concurrent.servicebaseline;

import core.atomic : atomicLoad, atomicOp;
import core.stdc.stdio : printf;
import flint.arena : Status;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.engine.reactor : OffloadWork, Reactor;
import flint.java.lang.interruptedexception : InterruptedException;
import flint.java.lang.runnable : Runnable;
import flint.java.lang.thread : InterruptSink, Thread;
import workload : Command, fixtureOptions;

@safe:

private final class NativeService
{
    private Runnable[2] pending;
    private bool completed;
    private shared uint wake;

    this(Runnable first, Runnable second)
    {
        pending = [first, second];
    }

    void dispatch() nothrow @nogc
    {
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();

        foreach (command; pending)
        {
            bool failed;
            scope OffloadWork work = () @safe nothrow{
                try
                    command.run();
                catch (Exception)
                    failed = true;
            };
            if (owner.offload(work).code != Status.ok || failed)
                return;
        }
        completed = true;
    }

    // The provider-equivalent termination wait: the same interruptible park as the leaf, without its API.
    bool await(long timeoutNanos)
    {
        long deadline = long.max;
        if (timeoutNanos != long.max)
        {
            const now = monotonicNow();
            const available = long.max - 1 - now;
            deadline = timeoutNanos >= available ? long.max - 1 : now + timeoutNanos;
        }
        auto state = Thread.currentThread().state();
        const token = state.install(InterruptSink(&this.signal));
        scope (exit)
        {
            if (token != 0)
                state.retire(token);
        }
        for (;;)
        {
            const observed = atomicLoad(wake);
            if (completed)
                return true;
            if (state.clearInterrupted())
                throw new InterruptedException;
            long sleep = maxParkNanos;
            if (deadline != long.max)
            {
                const now = monotonicNow();
                if (now >= deadline)
                    return completed;
                const remaining = deadline - now;
                if (remaining < sleep)
                    sleep = remaining;
            }
            if (sleep < 1)
                sleep = 1;
            park(wake, observed, sleep);
        }
    }

    private void signal() nothrow @nogc
    {
        atomicOp!"+="(wake, 1u);
        wakeAll(wake);
    }
}

private enum long maxParkNanos = 86_400_000_000_000L;

private long monotonicNow() nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds;
}

@system int main(string[] args)
{
    auto created = Reactor.create(fixtureOptions());
    if (!created.ok)
        return 1;

    auto first = new Command(1);
    auto second = new Command(2);
    auto service = new NativeService(first, second);
    bool valid;
    if (args.length == 1)
    {
        if (created.value.postStartup(0, &service.dispatch).code != Status.ok)
            return 1;
        valid = created.value.run().code == Status.ok && service.completed && service.await(0)
            && first.completed() && second.completed();
    }
    else
    {
        created.value.stop();
        valid = service.pending[0] is first && service.pending[1] is second && !first.completed()
            && !second.completed();
    }

    printf("%d\n", cast(int) !valid);
    return cast(int) !valid;
}
