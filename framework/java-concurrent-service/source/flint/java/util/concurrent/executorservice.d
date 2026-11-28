// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.concurrent.executorservice;

import core.atomic : atomicLoad, atomicStore, cas;
import core.lifetime : move;
import flint.arena : ReactorError = Error, Status;
import flint.conc : Deadline;
import flint.conc.slot : ProcessSlot;
import flint.engine.reactor : OffloadWork, Reactor, ReactorOptions, TaskContext;
import flint.java.lang : IllegalArgumentException, NullPointerException, RuntimeException;
import flint.java.lang.runnable : Runnable;
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
interface ExecutorService : Executor
{
    void shutdown();
    List!Runnable shutdownNow();
    bool isShutdown();
    bool isTerminated();

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
}

private long monotonicNow()
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
