// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 Future, implemented from the public contract.
module flint.java.util.concurrent.future;

import flint.java.lang : IllegalStateException;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.executionexception : ExecutionException;

@safe:

/// Java's `Future.State`, hoisted out of `Future` (R13).
enum FutureState
{
    /// The task has not completed.
    RUNNING,
    /// The task completed normally.
    SUCCESS,
    /// The task completed by throwing an exception.
    FAILED,
    /// The task was cancelled before it completed.
    CANCELLED,
}

/// Represents the result of an asynchronous computation.
interface Future(V)
{
    /// `Future.State` (R13).
    alias State = FutureState;

    /// Attempt to cancel the task. Returns false once it has completed or cannot be cancelled.
    bool cancel(bool mayInterruptIfRunning);

    /// Whether the task was cancelled before it completed normally.
    bool isCancelled();

    /// Whether the task completed, normally, exceptionally or by cancellation.
    bool isDone();

    /// Wait for completion and return the result, throwing ExecutionException if it failed.
    V get();

    /// Wait at most `timeout` of `unit` and return the result.
    V get(long timeout, TimeUnit unit);

    /// Return the result of a completed task, or throw IllegalStateException (R3).
    V resultNow();

    /// Return the exception of an exceptionally completed task, or throw IllegalStateException (R3).
    Throwable exceptionNow();

    /// Report the task's completion state (R3).
    State state();

    /// Java's default implementations, mixed in by implementors that want them (R3).
    mixin template Defaults()
    {
        typeof(this.get()) resultNow()
        {
            if (!isDone())
                throw new imported!"flint.java.lang".IllegalStateException("Task has not completed");
            if (isCancelled())
                throw new imported!"flint.java.lang".IllegalStateException("Task was cancelled");
            try
                return this.get();
            catch (imported!"flint.java.util.concurrent.executionexception".ExecutionException failure)
                throw new imported!"flint.java.lang".IllegalStateException("Task completed with exception", failure);
        }

        Throwable exceptionNow()
        {
            if (!isDone())
                throw new imported!"flint.java.lang".IllegalStateException("Task has not completed");
            if (isCancelled())
                throw new imported!"flint.java.lang".IllegalStateException("Task was cancelled");
            try
                this.get();
            catch (imported!"flint.java.util.concurrent.executionexception".ExecutionException failure)
                return failure.getCause();
            throw new imported!"flint.java.lang".IllegalStateException("Task completed with a result");
        }

        typeof(this).State state()
        {
            if (isCancelled())
                return typeof(this).State.CANCELLED;
            if (isDone())
            {
                try
                    this.get();
                catch (imported!"flint.java.util.concurrent.executionexception".ExecutionException failure)
                    return typeof(this).State.FAILED;
                return typeof(this).State.SUCCESS;
            }
            return typeof(this).State.RUNNING;
        }
    }
}
