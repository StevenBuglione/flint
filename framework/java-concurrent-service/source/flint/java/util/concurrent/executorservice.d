// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.concurrent.executorservice;

import core.atomic : atomicLoad, atomicStore, cas;
import core.lifetime : move;
import flint.arena : ReactorError = Error, Status;
import flint.conc.slot : ProcessSlot;
import flint.engine.reactor : OffloadWork, Reactor, ReactorOptions, TaskContext;
import flint.java.lang : IllegalArgumentException, NullPointerException, RuntimeException;
import flint.java.lang.runnable : Runnable;
import flint.java.util : ArrayList, List;
import flint.java.util.concurrent.executor : Executor;
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
