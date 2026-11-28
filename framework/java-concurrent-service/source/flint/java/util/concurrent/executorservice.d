// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.concurrent.executorservice;

import core.atomic : atomicLoad, atomicOp, atomicStore, cas;
import core.lifetime : move;
import flint.arena : ReactorError = Error, Status;
import flint.conc : Deadline;
import flint.conc.park : park, wakeAll;
import flint.conc.slot : ProcessSlot;
import flint.engine.reactor : OffloadWork, Reactor, ReactorOptions, TaskContext;
import flint.java.lang : AutoCloseable, IllegalArgumentException, NullPointerException, RuntimeException;
import flint.java.lang.interruptedexception : InterruptedException;
import flint.java.lang.runnable : Runnable;
import flint.java.lang.thread : InterruptSink, Thread, ThreadState;
import flint.java.util : ArrayList, Collection, List;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.executor : Executor;
import flint.java.util.concurrent.future : Future;
import flint.java.util.concurrent.futuretask : FutureTask;
import flint.java.util.concurrent.timeoutexception : TimeoutException;
import flint.java.util.concurrent.internal.executoradmissions : Admission, ExecutorAdmissions, ExecutorClaim;
import flint.java.util.concurrent.internal.executorrouting : ExecutorRoutes;
import flint.java.util.concurrent.internal.managedoffload : ManagedOffloadResult, invokeManaged;
import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;

public import flint.java.util.concurrent.internal.managedoffload : TaskFailureObserver;

@safe:

/// The execution and shutdown operations of a Java service.
interface ExecutorService : Executor, AutoCloseable
{
    void shutdown();
    List!Runnable shutdownNow();
    bool isShutdown();
    bool isTerminated();

    /// Wait at most `timeout` of `unit` for the service to terminate (R3, R9).
    ///
    /// Returns whether termination has happened. A task that interrupts the waiting thread ends the wait with
    /// `InterruptedException` and clears the flag, as Java's `Thread.interrupt` contract requires.
    bool awaitTermination(long timeout, TimeUnit unit);

    // Java 21's default `close` is implemented by `closeService` and forwarded by each concrete service, because
    // a D interface cannot give a default body to a method it inherits from another interface.

    /// Submit a value-returning task and return its future (R3, R9). Runs the task once through `execute`.
    Future!T submit(T)(Callable!T task)
    {
        auto future = new FutureTask!T(task);
        execute(future);
        return future;
    }

    /// Submit a task that returns `result` and return its future (R9).
    Future!T submit(T)(Runnable task, T result)
    {
        auto future = new FutureTask!T(task, result);
        execute(future);
        return future;
    }

    /// Submit a task with no value; the future's result is Java's `null` (R23).
    ///
    /// Java's `Future<?>` erases to `Future!Object`. The default type parameter makes the method a template so an
    /// application that never calls it links no completion code.
    Future!T submit(T = Object)(Runnable task) if (is(T == Object))
    {
        auto future = new FutureTask!T(task, T.init);
        execute(future);
        return future;
    }

    /// Execute every task and return its future once all have completed (R3, R9).
    ///
    /// Java's `invokeAll`: every future comes back in iteration order, and a task that failed or was cancelled
    /// reports through its own future rather than from this call. Interruption is deferred until the `Thread`
    /// façade lands, as it is for `Future.get`.
    List!(Future!T) invokeAll(T)(Collection!(Callable!T) tasks)
    {
        if (tasks is null)
            throw new NullPointerException;
        auto futures = new ArrayList!(Future!T)();
        bool done = false;
        scope (exit)
        {
            if (!done)
                foreach (i; 0 .. futures.size())
                    futures.get(i).cancel(true);
        }
        for (auto iterator = tasks.iterator(); iterator.hasNext();)
        {
            auto future = new FutureTask!T(iterator.next());
            futures.add(future);
            execute(future);
        }
        foreach (i; 0 .. futures.size())
        {
            auto future = futures.get(i);
            if (future.isDone())
                continue;
            try
                future.get();
            catch (CancellationException)
            {
            }
            catch (ExecutionException)
            {
            }
        }
        done = true;
        return futures;
    }

    /// Execute every task, waiting at most `timeout` of `unit` (R3, R9).
    ///
    /// As Java's timed `invokeAll`: an unfinished future is cancelled and returned, and a timeout is reported by
    /// those futures rather than by throwing `TimeoutException`.
    List!(Future!T) invokeAll(T)(Collection!(Callable!T) tasks, long timeout, TimeUnit unit)
    {
        if (tasks is null)
            throw new NullPointerException;
        const nanos = toNanos(unit, timeout);
        auto futures = new ArrayList!(Future!T)();
        bool done = false;
        scope (exit)
        {
            if (!done)
                foreach (i; 0 .. futures.size())
                    futures.get(i).cancel(true);
        }
        for (auto iterator = tasks.iterator(); iterator.hasNext();)
            futures.add(new FutureTask!T(iterator.next()));

        // Java starts the deadline once the tasks are collected, then counts it down over submission and waiting.
        const deadline = saturatingAdd(monotonicNow(), nanos);
        const size = futures.size();
        foreach (i; 0 .. size)
        {
            if (remainingNanos(deadline) <= 0)
                return futures;
            execute(cast(Runnable) futures.get(i));
        }
        foreach (i; 0 .. size)
        {
            auto future = futures.get(i);
            if (future.isDone())
                continue;
            const remaining = remainingNanos(deadline);
            if (remaining <= 0)
                return futures;
            try
                future.get(remaining, TimeUnit.NANOSECONDS);
            catch (CancellationException)
            {
            }
            catch (ExecutionException)
            {
            }
            catch (TimeoutException)
            {
                return futures;
            }
        }
        done = true;
        return futures;
    }

    /// Execute the tasks and return one result that completed successfully (R3, R9).
    ///
    /// As Java's `invokeAny`: the tasks still running are cancelled when this returns or throws, failures are
    /// reported as the last `ExecutionException`, and an empty collection is rejected.
    T invokeAny(T)(Collection!(Callable!T) tasks)
    {
        return invokeAnyImpl(this, tasks, false, 0);
    }

    /// Execute the tasks and return one result that completed before `timeout` (R3, R9).
    ///
    /// As Java's timed `invokeAny`: `TimeoutException` is thrown when no task completes in time.
    T invokeAny(T)(Collection!(Callable!T) tasks, long timeout, TimeUnit unit)
    {
        return invokeAnyImpl(this, tasks, true, toNanos(unit, timeout));
    }
}

// The tasks `invokeAny` has submitted complete here. Each completion publishes its finished future and advances
// `wake`, so the waiting fiber or thread parks until something completes instead of polling [R-10].
private final class CompletionQueue(T)
{
    private Future!T[] ready;
    private size_t head;
    private shared uint wake = 0;

    void add(Future!T future) @safe
    {
        synchronized (this)
            ready ~= future;
        signal();
    }

    bool poll(out Future!T future) @safe
    {
        synchronized (this)
        {
            if (head == ready.length)
                return false;
            future = ready[head++];
            if (head == ready.length)
            {
                ready = null;
                head = 0;
            }
            return true;
        }
    }

    // Advance the word and wake every parked waiter. Called after a completion is published.
    void signal() nothrow @nogc
    {
        atomicOp!"+="(wake, 1u);
        wakeAll(wake);
    }
}

// Run a future and publish it only afterwards, so a waiter that sees it in the queue sees a finished future.
private final class CompletionTask(T) : Runnable
{
    private FutureTask!T future;
    private CompletionQueue!T queue;

    this(FutureTask!T future, CompletionQueue!T queue)
    {
        this.future = future;
        this.queue = queue;
    }

    override void run()
    {
        scope (exit)
            queue.add(future);
        future.run();
    }
}

// Wait for the next completion, parking on the queue's word until `deadline` (long.max for no timeout). An
// interrupt of the calling thread ends the wait with `InterruptedException`, as Java's completion-queue take does.
private bool awaitCompletion(T)(CompletionQueue!T queue, out Future!T future, long deadline,
        ref ThreadState state, ulong token)
{
    for (;;)
    {
        // Read the wake word before the queue: a completion or interrupt between the two observations then
        // advances the word and ends the park below, instead of leaving the waiter asleep.
        const observed = atomicLoad(queue.wake);
        if (queue.poll(future))
            return true;
        if (state.clearInterrupted())
            throw new InterruptedException;
        bool expired;
        long sleep = parkNanos(deadline, expired);
        if (expired)
            return false;
        // A waiter that could not install its sink (another wait is active) still sees the flag.
        if (token == 0 && sleep > interruptPollNanos)
            sleep = interruptPollNanos;
        park(queue.wake, observed, sleep);
    }
}

// Cancel every future `invokeAny` submitted, leaving completed ones untouched (Java's `cancelAll`).
private void cancelStarted(T)(ArrayList!(Future!T) futures)
{
    foreach (i; 0 .. futures.size())
        futures.get(i).cancel(true);
}

// Java's `f.get()` inside doInvokeAny: a success returns the value, and a failure is remembered so the last one
// can be thrown once every task has finished.
private enum AnyOutcome
{
    success,
    failed,
}

private AnyOutcome takeResult(T)(Future!T future, out T result, ref ExecutionException lastFailure)
{
    try
    {
        result = future.get();
        return AnyOutcome.success;
    }
    catch (ExecutionException failure)
        lastFailure = failure;
    catch (RuntimeException failure)
        lastFailure = new ExecutionException(failure);
    return AnyOutcome.failed;
}

// Java's `AbstractExecutorService.doInvokeAny`: submit incrementally, return the first success, remember the last
// failure, and cancel every submitted task on the way out.
package(flint.java.util.concurrent) T invokeAnyImpl(T)(ExecutorService service,
        Collection!(Callable!T) tasks, bool timed, long nanos)
{
    if (tasks is null)
        throw new NullPointerException;
    if (tasks.isEmpty())
        throw new IllegalArgumentException;
    auto queue = new CompletionQueue!T;
    auto futures = new ArrayList!(Future!T)();
    scope (exit)
        cancelStarted(futures);

    auto state = Thread.currentThread().state();
    const token = state.install(InterruptSink(&queue.signal));
    scope (exit)
    {
        if (token != 0)
            state.retire(token);
    }

    auto iterator = tasks.iterator();
    const deadline = timed ? saturatingAdd(monotonicNow(), nanos) : long.max;
    ExecutionException lastFailure;
    int active = 0;

    void submitNext() @safe
    {
        auto future = new FutureTask!T(iterator.next());
        service.execute(new CompletionTask!T(future, queue));
        futures.add(future);
        active++;
    }

    submitNext();
    for (;;)
    {
        Future!T future;
        if (!queue.poll(future))
        {
            if (iterator.hasNext())
            {
                submitNext();
                continue;
            }
            if (active == 0)
                break;
            if (!awaitCompletion(queue, future, deadline, state, token))
                throw new TimeoutException;
        }
        active--;
        T result;
        if (takeResult(future, result, lastFailure) == AnyOutcome.success)
            return result;
    }
    if (lastFailure is null)
        lastFailure = ExecutionException.withoutCause();
    throw lastFailure;
}

// Java 21's default `close`: shut down, wait for termination, and restore an interrupt that ended the wait.
package(flint.java.util.concurrent) void closeService(ExecutorService service)
{
    bool terminated = service.isTerminated();
    if (terminated)
        return;
    service.shutdown();
    bool interrupted = false;
    while (!terminated)
    {
        try
            terminated = service.awaitTermination(1, TimeUnit.DAYS);
        catch (InterruptedException)
        {
            if (!interrupted)
            {
                service.shutdownNow();
                interrupted = true;
            }
        }
    }
    if (interrupted)
        Thread.currentThread().interrupt();
}

private long monotonicNow() nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds;
}

private long saturatingAdd(long value, long delta)
{
    const sum = value + delta;
    if (delta > 0 && sum < value)
        return long.max;
    if (delta < 0 && sum > value)
        return long.min;
    return sum;
}

private long remainingNanos(long deadline)
{
    if (deadline == long.max)
        return long.max;
    return deadline - monotonicNow();
}

// Bound a single park so a platform timeout that takes a 32-bit millisecond count cannot overflow.
private enum long maxParkNanos = 86_400_000_000_000L;

// A waiter that cannot install its interrupt sink because another wait is active still polls the flag.
private enum long interruptPollNanos = 10_000_000L;

// The next bounded park, or `expired` once a timed wait has reached its deadline.
private long parkNanos(long deadline, out bool expired) nothrow @nogc
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

private shared ProcessSlot!ExecutorRoutes routeTable;

private ExecutorRoutes serviceRoutes()
{
    auto routes = routeTable.get();
    if (routes !is null)
        return routes;
    return routeTable.setIfAbsent(new ExecutorRoutes(ushort.max));
}

/// A bounded offload executor with a reactor owned by its D host.
final class OffloadExecutorService : ExecutorService
{
    private Reactor reactor;
    private ExecutorAdmissions queue;
    private ExecutorRoutes routes;
    private Runnable[] undelivered;
    private shared bool driverStarted;
    private shared bool driverFinished;
    // Advanced whenever the service can have changed termination state; the word an `awaitTermination` parks on.
    private shared uint wake = 0;

    /// Bind the service to reactor owner zero. By default it uses one owner
    /// and one offload thread. Call run once on a registered D thread.
    this(uint pendingCapacity, ReactorOptions options = ReactorOptions.init, TaskFailureObserver observer = null)
    {
        if (pendingCapacity == 0 || pendingCapacity > int.max)
            throw new IllegalArgumentException("invalid pending capacity");
        if (options.cores == 0)
            options.cores = 1;
        if (options.offloadThreads == 0)
            options.offloadThreads = 1;
        auto created = Reactor.create(options);
        if (!created.ok)
            throw new RuntimeException(created.error.message);
        reactor = move(created.value);
        queue = new ExecutorAdmissions(pendingCapacity, observer);
        routes = serviceRoutes();
    }

    override void execute(Runnable command)
    {
        const admission = routes.admit(queue, command, (ulong token) => reactor.post(0, &dispatch,
                TaskContext(token)).code == Status.ok);
        if (admission == Admission.invalidCommand)
            throw new NullPointerException;
        if (admission != Admission.accepted)
            throw new RejectedExecutionException("executor rejected the task");
    }

    override void shutdown()
    {
        queue.shutdown();
        if (queue.isTerminated())
            reactor.stop();
        signal();
    }

    override List!Runnable shutdownNow()
    {
        synchronized (this)
        {
            auto pending = routes.shutdownNow(queue);
            if (undelivered.length != 0)
            {
                // The driver already detached the queue when it captured these tasks.
                assert(pending.length == 0);
                pending = undelivered;
                undelivered = null;
            }
            reactor.stop();
            signal();
            return new ArrayList!Runnable(pending);
        }
    }

    override bool isShutdown()
    {
        return queue.isShutdown();
    }

    override bool isTerminated()
    {
        return atomicLoad(driverFinished) || (!atomicLoad(driverStarted) && queue.isTerminated());
    }

    override bool awaitTermination(long timeout, TimeUnit unit)
    {
        const deadline = saturatingAdd(monotonicNow(), toNanos(unit, timeout));
        auto state = Thread.currentThread().state();
        const token = state.install(InterruptSink(&this.signal));
        scope (exit)
        {
            if (token != 0)
                state.retire(token);
        }
        for (;;)
        {
            // Read the wake word before the state: a termination or interrupt between the two observations then
            // advances the word and ends the park below, instead of leaving the waiter asleep.
            const observed = atomicLoad(wake);
            if (isTerminated())
                return true;
            if (state.clearInterrupted())
                throw new InterruptedException;
            bool expired;
            long sleep = parkNanos(deadline, expired);
            if (expired)
                return isTerminated();
            // A waiter that could not install its sink (another wait is active) still sees the flag.
            if (token == 0 && sleep > interruptPollNanos)
                sleep = interruptPollNanos;
            park(wake, observed, sleep);
        }
    }

    override void close()
    {
        closeService(this);
    }

    // Advance the wake word and end every parked waiter. Called on every termination-state change.
    private void signal() nothrow @nogc
    {
        atomicOp!"+="(wake, 1u);
        wakeAll(wake);
    }

    /// Drive the owned reactor to completion. Withdraw routes that could not
    /// reach a stopped reactor and keep their tasks available to shutdownNow.
    ReactorError run()
    {
        if (!cas(&driverStarted, false, true))
            return ReactorError(Status.conflict, "executor reactor already driven");
        scope (exit)
        {
            synchronized (this)
            {
                undelivered = routes.shutdownNow(queue);
                atomicStore(driverFinished, true);
                signal();
            }
        }
        return queue.isTerminated() ? ReactorError.init : reactor.run();
    }

    package(flint.java.util.concurrent) void requestStop() nothrow @nogc
    {
        reactor.stop();
    }

    private static void dispatch() nothrow @nogc
    {
        auto owner = Reactor.current();
        auto task = owner.currentTask();
        assert(task.ok);
        auto queue = routeTable.get().takePermit(task.value.requestId);
        if (queue is null)
            return;

        ExecutorClaim active;
        Exception failure;
        scope OffloadWork work = () @safe nothrow{
            if (queue.tryStart(active))
                failure = invokeManaged(active.command);
        };
        // The pool publishes these worker writes before offload returns.
        auto status = owner.offload(work);
        if (active.command !is null)
        {
            scope (exit)
            {
                queue.retire(active);
                if (queue.isTerminated())
                    owner.stop();
            }
            queue.reportFailure(active.command, ManagedOffloadResult(status, failure));
        }
    }
}
