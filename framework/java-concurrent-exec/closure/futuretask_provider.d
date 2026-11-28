module flint.java.util.concurrent.internal.futuretaskcontrol;

import core.atomic : atomicLoad, atomicOp, atomicStore, cas;
import flint.conc.park : park, wakeAll;
import flint.java.lang.interruptedexception : InterruptedException;
import flint.java.lang.thread : InterruptSink, Thread, ThreadState;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

private enum uint NEW = 0;
private enum uint RUNNING = 1;
private enum uint COMPLETING = 2;
private enum uint NORMAL = 3;
private enum uint EXCEPTIONAL = 4;
private enum uint CANCELLED = 5;
private enum long maxParkNanos = 86_400_000_000_000L;

// A provider-equivalent task: the same state machine and park/wake calls without the Java leaf.
private final class Station
{
    private shared uint status = NEW;
    private shared uint wake = 0;
    private int result;

    this(int result) pure nothrow @nogc
    {
        this.result = result;
    }

    void run()
    {
        if (!cas(&status, NEW, RUNNING))
            return;
        if (!cas(&status, RUNNING, COMPLETING))
            return;
        atomicStore(status, NORMAL);
        signal();
    }

    bool cancel()
    {
        for (;;)
        {
            const current = atomicLoad(status);
            if (current == NEW)
            {
                if (cas(&status, current, CANCELLED))
                {
                    signal();
                    return true;
                }
                continue;
            }
            return current == CANCELLED;
        }
    }

    bool isDone()
    {
        return atomicLoad(status) >= NORMAL;
    }

    bool isCancelled()
    {
        return atomicLoad(status) == CANCELLED;
    }

    int get(long timeout, TimeUnit unit)
    {
        const timeoutNanos = toNanos(unit, timeout);
        long deadline = long.max;
        if (timeoutNanos >= 0)
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
            const current = atomicLoad(status);
            if (current >= NORMAL)
                break;
            if (state.clearInterrupted())
                throw new InterruptedException;
            long sleep = maxParkNanos;
            if (deadline != long.max)
            {
                const now = monotonicNow();
                if (now >= deadline)
                {
                    if (atomicLoad(status) < NORMAL)
                        throw new TimeoutException;
                    break;
                }
                const remaining = deadline - now;
                if (remaining < sleep)
                    sleep = remaining;
            }
            if (sleep < 1)
                sleep = 1;
            park(wake, observed, sleep);
        }
        if (atomicLoad(status) == CANCELLED)
            throw new Exception("cancelled");
        return result;
    }

    private void signal() nothrow @nogc
    {
        atomicOp!"+="(wake, 1u);
        wakeAll(wake);
    }

    private static long monotonicNow()
    {
        import flint.conc : Deadline;

        return Deadline.afterMillis(0).monotonicNanoseconds;
    }
}

int main(string[] args)
{
    auto task = new Station(cast(int) args.length);
    if (args.length > 2)
    {
        if (!task.cancel())
            return 1;
        try
            return task.get(0, TimeUnit.init) == 0 ? 0 : 1;
        catch (Exception)
            return 0;
    }
    task.run();
    if (!task.isDone || task.isCancelled)
        return 1;
    return task.get(1, TimeUnit.init) == cast(int) args.length ? 0 : 1;
}
