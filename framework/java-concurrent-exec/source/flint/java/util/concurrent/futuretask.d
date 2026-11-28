// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 FutureTask, implemented from the public contract.
module flint.java.util.concurrent.futuretask;

import core.atomic : atomicLoad, atomicStore, cas;
import flint.conc.park : park, wakeAll;
import flint.java.lang : NullPointerException, RuntimeException;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.future : Future, RunnableFuture;
import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

/++
Java's `FutureTask`: the cancellable result of a `Runnable` or `Callable` that is run once.

The task's state is a single 32-bit word shared between the running thread and its waiters. A waiter parks on that
word with `flint.conc.park`, so an owner fiber yields to its reactor instead of spinning. The result and the failure
are published before the state word, and every reader observes them through the acquire in `atomicLoad` [R-193].
+/
final class FutureTask(V) : RunnableFuture!V
{
    mixin Future!V.Defaults;

    private enum uint NEW = 0;
    private enum uint RUNNING = 1;
    private enum uint COMPLETING = 2;
    private enum uint NORMAL = 3;
    private enum uint EXCEPTIONAL = 4;
    private enum uint CANCELLED = 5;

    // Bound a single park so a platform timeout that takes a 32-bit millisecond count cannot overflow.
    private enum long maxParkNanos = 86_400_000_000_000L;

    private shared uint status = NEW;
    private Callable!V callable;
    private Runnable runnable;
    private V runnableResult;
    private V value;
    private Throwable failure;

    /// Wrap a `Callable`.
    this(Callable!V callable)
    {
        if (callable is null)
            throw new NullPointerException;
        this.callable = callable;
    }

    /// Wrap a `Runnable` whose `run` returns `result`.
    this(Runnable runnable, V result)
    {
        if (runnable is null)
            throw new NullPointerException;
        this.runnable = runnable;
        this.runnableResult = result;
    }

    /// Run the wrapped task once. A second call, or a call after cancellation, does nothing.
    override void run()
    {
        if (!cas(&status, NEW, RUNNING))
            return;

        V produced;
        Throwable thrown;
        bool succeeded = true;
        scope (failure)
        {
            // A D `Error` cannot be caught in `@safe` code (Java's FutureTask stores it). Publish a failure so a
            // waiter never blocks forever, and let the error propagate to the caller.
            if (cas(&status, RUNNING, COMPLETING))
            {
                failure = new RuntimeException("task failed");
                atomicStore(status, EXCEPTIONAL);
                wakeAll(status);
            }
        }
        try
        {
            if (callable !is null)
                produced = callable.call();
            else
            {
                runnable.run();
                produced = runnableResult;
            }
        }
        catch (Exception failure)
        {
            thrown = failure;
            succeeded = false;
        }

        // A concurrent cancel(true) moved the state out of RUNNING: discard the result.
        if (!cas(&status, RUNNING, COMPLETING))
            return;
        value = produced;
        this.failure = thrown;
        atomicStore(status, succeeded ? NORMAL : EXCEPTIONAL);
        wakeAll(status);
    }

    /// Cancel before the result is published. Java's thread interruption is deferred until the `Thread` façade lands.
    override bool cancel(bool mayInterruptIfRunning)
    {
        for (;;)
        {
            const current = atomicLoad(status);
            if (current == NEW || (current == RUNNING && mayInterruptIfRunning))
            {
                if (cas(&status, current, CANCELLED))
                {
                    wakeAll(status);
                    return true;
                }
                continue;
            }
            return current == CANCELLED;
        }
    }

    /// Whether the task was cancelled before it completed.
    override bool isCancelled()
    {
        return atomicLoad(status) == CANCELLED;
    }

    /// Whether the task completed normally, exceptionally or by cancellation.
    override bool isDone()
    {
        return atomicLoad(status) >= NORMAL;
    }

    /// Wait for completion and return the result or throw `ExecutionException`.
    override V get()
    {
        awaitDone(long.max, false);
        return report();
    }

    /// Wait at most `timeout` of `unit` and return the result or throw `ExecutionException`/`TimeoutException`.
    override V get(long timeout, TimeUnit unit)
    {
        if (!awaitDone(toNanos(unit, timeout), true))
            throw new TimeoutException;
        return report();
    }

    private V report()
    {
        const current = atomicLoad(status);
        if (current == CANCELLED)
            throw new CancellationException;
        if (current == EXCEPTIONAL)
        {
            // Java rethrows a stored CancellationException unchanged and wraps everything else.
            if (auto cancelled = cast(CancellationException) failure)
                throw cancelled;
            throw new ExecutionException(failure);
        }
        return value;
    }

    // Java's `get` and `get(timeout)`: `timed` selects the bounded form, and a nonpositive timeout times out at once.
    private bool awaitDone(long timeoutNanos, bool timed)
    {
        long deadline = long.max;
        if (timed)
        {
            if (timeoutNanos <= 0)
                return atomicLoad(status) >= NORMAL;
            const now = monotonicNow();
            const available = long.max - 1 - now;
            deadline = timeoutNanos >= available ? long.max - 1 : now + timeoutNanos;
        }

        for (;;)
        {
            const current = atomicLoad(status);
            if (current >= NORMAL)
                return true;

            long sleep = maxParkNanos;
            if (deadline != long.max)
            {
                const now = monotonicNow();
                if (now >= deadline)
                    return atomicLoad(status) >= NORMAL;
                const remaining = deadline - now;
                if (remaining < sleep)
                    sleep = remaining;
            }
            if (sleep < 1)
                sleep = 1;
            park(status, current, sleep);
        }
    }

    private static long monotonicNow()
    {
        import flint.conc : Deadline;

        return Deadline.afterMillis(0).monotonicNanoseconds;
    }
}
