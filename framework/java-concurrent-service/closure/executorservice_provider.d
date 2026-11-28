module flint.java.util.concurrent.internal.executorservicecontrol;

import core.atomic : atomicLoad, atomicOp;
import flint.arena : Status;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.engine.reactor : OffloadWork, Reactor, ReactorOptions;
import flint.java.lang.interruptedexception : InterruptedException;
import flint.java.lang.runnable : Runnable;
import flint.java.lang.thread : InterruptSink, Thread;

@safe:

private final class Command : Runnable
{
    int[] result;

    override void run()
    {
        result = [7];
    }
}

private final class NativeDispatch
{
    private Runnable pending;
    bool completed;
    private shared uint wake;

    this(Runnable pending)
    {
        this.pending = pending;
    }

    void dispatch() nothrow @nogc
    {
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();

        bool failed;
        scope OffloadWork work = () @safe nothrow{
            try
                pending.run();
            catch (Exception)
                failed = true;
        };
        completed = owner.offload(work).code == Status.ok && !failed;
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

int main(string[] args)
{
    ReactorOptions options;
    options.cores = 1;
    options.offloadThreads = 1;
    auto created = Reactor.create(options);
    if (!created.ok)
        return 1;

    auto task = new Command;
    auto dispatch = new NativeDispatch(task);
    if (created.value.postStartup(0, &dispatch.dispatch).code != Status.ok)
        return 1;

    if (args.length > 1)
    {
        created.value.stop();
        return dispatch.pending is task && task.result is null && dispatch.await(0) ? 0 : 1;
    }

    return created.value.run().code == Status.ok && dispatch.completed && dispatch.await(0)
        && task.result.length == 1 && task.result[0] == 7 ? 0 : 1;
}
