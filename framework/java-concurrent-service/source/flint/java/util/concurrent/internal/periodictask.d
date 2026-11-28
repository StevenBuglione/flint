// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// The repeating task behind Java's periodic scheduling forms (leaf-private).
module flint.java.util.concurrent.internal.periodictask;

import core.atomic : atomicLoad, atomicStore, cas;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent : TimeUnit, convert, toNanos;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.future : Future, FutureState;
import flint.java.util.concurrent.scheduledfuture : RunnableScheduledFuture;
import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

// The service stores this interface in its queue, so scheduling never needs a runtime downcast from Runnable.
package(flint.java.util.concurrent) interface PeriodicHost
{
    void reschedule(PeriodicControl task);
}

package(flint.java.util.concurrent) interface PeriodicControl : Runnable
{
    void attach(PeriodicHost host, long periodNanos, bool fixedRate) nothrow @nogc;
    long periodNanos() nothrow @nogc;
    bool fixedRate() nothrow @nogc;
    long dueNanos() nothrow @nogc;
    void setDue(long nanos) nothrow @nogc;
    bool cancelNow() nothrow @nogc;
    bool isDoneNow() nothrow @nogc;
}

/// A future for a task that runs repeatedly until it is cancelled or throws (R1, R3).
///
/// Java's periodic `ScheduledFutureTask` keeps one `FutureTask` in `NEW` between runs through `runAndReset`; here
/// the flags are the observable state. `get` returns only by cancellation (`CancellationException`) or by the task's
/// exception (`ExecutionException`), and both are published before the wake word's release.
package(flint.java.util.concurrent) final class PeriodicTask : RunnableScheduledFuture!Object, PeriodicControl
{
    private enum long maxParkNanos = 86_400_000_000_000L;

    private Runnable command;
    private shared uint cancelled;
    private shared uint failed;
    private shared long due;
    private shared uint wake;
    private Throwable failure;
    private long period;
    private bool repeatsAtRate;
    private PeriodicHost host;

    this(Runnable command) pure nothrow @nogc
    {
        this.command = command;
    }

    /// Publish the absolute deadline the worker will observe (D-only, from the service).
    void setDue(long nanos) nothrow @nogc
    {
        atomicStore(due, nanos);
    }

    /// The current absolute deadline (D-only, read by the service's reschedule hook).
    long dueNanos() nothrow @nogc
    {
        return atomicLoad(due);
    }

    /// Install the service's reschedule step and repetition policy (D-only).
    void attach(PeriodicHost host, long periodNanos, bool fixedRate) nothrow @nogc
    {
        this.host = host;
        this.period = periodNanos;
        this.repeatsAtRate = fixedRate;
    }

    /// The repetition period in nanoseconds (D-only, read by the service's reschedule hook).
    long periodNanos() nothrow @nogc
    {
        return period;
    }

    /// Whether the period is the start-to-start rate rather than the run-to-run delay.
    bool fixedRate() nothrow @nogc
    {
        return repeatsAtRate;
    }

    /// Whether the task has stopped repeating: cancelled or threw.
    bool isDoneNow() nothrow @nogc
    {
        return atomicLoad(cancelled) != 0 || atomicLoad(failed) != 0;
    }

    /// Cancel the repetition; a run in flight is not interrupted (deferred until the Thread façade lands).
    bool cancelNow() nothrow @nogc
    {
        if (atomicLoad(failed) != 0)
            return false;
        if (!cas(&cancelled, 0u, 1u))
            return false;
        wakeAll(wake);
        return true;
    }

    override void run()
    {
        if (atomicLoad(cancelled) != 0 || atomicLoad(failed) != 0)
            return;
        scope (failure)
        {
            // A D `Error` cannot be caught in `@safe` code. Publish a failure so a waiter never blocks forever.
            if (atomicLoad(cancelled) == 0 && cas(&failed, 0u, 1u))
                wakeAll(wake);
        }
        try
            command.run();
        catch (Exception thrown)
        {
            // A concurrent cancel wins, as Java's `setException` on a cancelled FutureTask does.
            if (atomicLoad(cancelled) == 0)
            {
                failure = thrown;
                if (cas(&failed, 0u, 1u))
                    wakeAll(wake);
            }
            return;
        }
        if (atomicLoad(cancelled) == 0 && atomicLoad(failed) == 0 && host !is null)
            host.reschedule(this);
    }

    override bool cancel(bool mayInterruptIfRunning)
    {
        return cancelNow();
    }

    override bool isCancelled()
    {
        return atomicLoad(cancelled) != 0;
    }

    override bool isDone()
    {
        return isDoneNow();
    }

    override Object get()
    {
        awaitDone(long.max, false);
        return report();
    }

    override Object get(long timeout, TimeUnit unit)
    {
        awaitDone(toNanos(unit, timeout), true);
        return report();
    }

    /// Return the completed result, or throw IllegalStateException (R3).
    override Object resultNow()
    {
        if (!isDone())
            throw new IllegalStateException("Task has not completed");
        if (isCancelled())
            throw new IllegalStateException("Task was cancelled");
        try
            return get();
        catch (ExecutionException failure)
            throw new IllegalStateException("Task completed with exception", failure);
    }

    /// Return the exception of an exceptionally completed task, or throw IllegalStateException (R3).
    override Throwable exceptionNow()
    {
        if (!isDone())
            throw new IllegalStateException("Task has not completed");
        if (isCancelled())
            throw new IllegalStateException("Task was cancelled");
        try
            get();
        catch (ExecutionException failure)
            return failure.getCause();
        throw new IllegalStateException("Task completed with a result");
    }

    /// Report the task's completion state (R3).
    override FutureState state()
    {
        if (isCancelled())
            return FutureState.CANCELLED;
        if (isDone())
        {
            try
                get();
            catch (ExecutionException)
                return FutureState.FAILED;
            return FutureState.SUCCESS;
        }
        return FutureState.RUNNING;
    }

    /// Java's delay in `unit`: the next deadline minus the current monotonic time, truncated toward zero (R20).
    override long getDelay(TimeUnit unit)
    {
        return convert(unit, atomicLoad(due) - monotonicNow(), TimeUnit.NANOSECONDS);
    }

    /// Order by the next deadline, as Java's `RunnableScheduledFuture` does (R1, R3).
    override int compareTo(Delayed other)
    {
        if (other is this)
            return 0;
        if (other is null)
            throw new NullPointerException;
        const mine = getDelay(TimeUnit.NANOSECONDS);
        const theirs = other.getDelay(TimeUnit.NANOSECONDS);
        return mine < theirs ? -1 : mine > theirs ? 1 : 0;
    }

    /// A periodic schedule repeats until cancelled.
    override bool isPeriodic() pure nothrow @nogc
    {
        return true;
    }

    private Object report()
    {
        if (atomicLoad(cancelled) != 0)
            throw new CancellationException;
        throw new ExecutionException(failure);
    }

    private void awaitDone(long timeoutNanos, bool timed)
    {
        long deadline = long.max;
        if (timed)
        {
            if (timeoutNanos <= 0)
            {
                if (isDoneNow())
                    return;
                throw new TimeoutException;
            }
            const now = monotonicNow();
            const available = long.max - 1 - now;
            deadline = timeoutNanos >= available ? long.max - 1 : now + timeoutNanos;
        }

        for (;;)
        {
            const seen = atomicLoad(wake);
            if (isDoneNow())
                return;
            long sleep = maxParkNanos;
            if (deadline != long.max)
            {
                const now = monotonicNow();
                if (now >= deadline)
                {
                    if (isDoneNow())
                        return;
                    throw new TimeoutException;
                }
                const remaining = deadline - now;
                if (remaining < sleep)
                    sleep = remaining;
            }
            if (sleep < 1)
                sleep = 1;
            park(wake, seen, sleep);
        }
    }
}

private long monotonicNow() nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds;
}
