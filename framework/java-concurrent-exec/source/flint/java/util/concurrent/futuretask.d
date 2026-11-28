// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 FutureTask, implemented from the public contract.
module flint.java.util.concurrent.futuretask;

import core.atomic : atomicLoad, atomicOp, atomicStore, cas;
import flint.conc.park : park, wakeAll;
import flint.java.lang : NullPointerException, RuntimeException;
import flint.java.lang.interruptedexception : InterruptedException;
import flint.java.lang.runnable : Runnable;
import flint.java.lang.thread : InterruptSink, Thread, ThreadState;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.future : Future, RunnableFuture;
import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

/++
Java's `FutureTask`: the cancellable result of a `Runnable` or `Callable` that is run once.

The task's state is a single 32-bit word shared between the running thread and its waiters. A waiter parks on a
separate wake word with `flint.conc.park`, so an owner fiber yields to its reactor instead of spinning. Completion,
cancellation and an installed interrupt each advance the wake word, so none of them can be lost between a waiter's
check and its park. The result and the failure are published before the state word, and every reader observes them
through the acquire in `atomicLoad` [R-193]. An interruptible `get` installs a `ThreadState.InterruptSink`; on waking
it re-checks the state first, then clears the interrupt flag and throws `InterruptedException`, as Java does.
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

    // A thread that cannot install its interrupt sink because another wait is active still polls the flag.
    private enum long interruptPollNanos = 10_000_000L;

    private shared uint status = NEW;
    // Advanced by completion, cancellation and an installed interrupt; the word a waiter parks on.
    private shared uint wake = 0;
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
                signal();
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
        signal();
    }

    /// Cancel before the result is published. Java's thread interruption is deferred until the `Thread` façade lands.
    ///
    /// Java's `FutureTask` stays in its start state while the callable runs, so a cancel succeeds then too and the
    /// eventual result is discarded; once completion begins, or after any terminal state, it returns false.
    override bool cancel(bool mayInterruptIfRunning)
    {
        for (;;)
        {
            const current = atomicLoad(status);
            if (current >= COMPLETING)
                return false;
            if (cas(&status, current, CANCELLED))
            {
                signal();
                return true;
            }
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

    /// Wait for completion and return the result or throw `ExecutionException`/`InterruptedException`.
    override V get()
    {
        awaitDone(long.max, false, true);
        return report();
    }

    /// Wait at most `timeout` of `unit` and return the result or throw `ExecutionException`/`TimeoutException`/
    /// `InterruptedException`.
    override V get(long timeout, TimeUnit unit)
    {
        if (!awaitDone(toNanos(unit, timeout), true, true))
            throw new TimeoutException;
        return report();
    }

    private V report()
    {
        const current = atomicLoad(status);
        if (current == CANCELLED)
            throw new CancellationException;
        if (current == EXCEPTIONAL)
            throw new ExecutionException(failure);
        return value;
    }

    // Java's `get` and `get(timeout)`: `timed` selects the bounded form, and a nonpositive timeout times out at once.
    // `interruptible` installs the calling thread's interrupt sink for the whole wait.
    private bool awaitDone(long timeoutNanos, bool timed, bool interruptible)
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

        ThreadState state;
        ulong token;
        if (interruptible)
        {
            state = Thread.currentThread().state();
            token = state.install(InterruptSink(&this.signal));
        }
        scope (exit)
        {
            if (token != 0)
                state.retire(token);
        }

        for (;;)
        {
            // Read the wake word before the state: a completion or interrupt between the two observations then
            // advances the word and ends the park below, instead of leaving the waiter asleep.
            const observed = atomicLoad(wake);
            const current = atomicLoad(status);
            if (current >= NORMAL)
                return true;
            if (interruptible && state.clearInterrupted())
                throw new InterruptedException;

            bool expired;
            long sleep = parkNanos(deadline, expired);
            if (expired)
                return atomicLoad(status) >= NORMAL;
            // A waiter that could not install its sink (another wait is active) still sees the flag.
            if (interruptible && token == 0 && sleep > interruptPollNanos)
                sleep = interruptPollNanos;
            park(wake, observed, sleep);
        }
    }

    // Advance the wake word and end every waiter's park. Called after the outcome is published.
    private void signal() nothrow @nogc
    {
        atomicOp!"+="(wake, 1u);
        wakeAll(wake);
    }

    // The next bounded park, or `expired` once a timed wait has reached its deadline.
    private static long parkNanos(long deadline, out bool expired) nothrow @nogc
    {
        expired = false;
        if (deadline == long.max)
            return maxParkNanos;
        const now = monotonicNow();
        if (now >= deadline)
        {
            expired = true;
            return 0;
        }
        const remaining = deadline - now;
        return remaining < maxParkNanos ? remaining : maxParkNanos;
    }

    private static long monotonicNow()
    {
        import flint.conc : Deadline;

        return Deadline.afterMillis(0).monotonicNanoseconds;
    }
}
