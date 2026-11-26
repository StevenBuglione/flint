// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.concurrent.internal.executoradmissions;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, casWeak, pause;
import flint.arena : Status;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.internal.managedoffload : ManagedOffloadResult, TaskFailureObserver;

@safe:

private alias TrackedPost = bool delegate(out ulong) @safe nothrow @nogc;

package(flint.java.util.concurrent) enum Admission : ubyte
{
    accepted,
    invalidCommand,
    closed,
    full,
    unavailable,
}

package(flint.java.util.concurrent) struct ExecutorClaim
{
    private ExecutorAdmissions owner;
    private Runnable task;

    @disable this(this);

    Runnable command() pure nothrow @nogc
    {
        return task;
    }
}

package(flint.java.util.concurrent) final class ExecutorAdmissions
{
    private enum Phase : ubyte
    {
        open,
        draining,
        stopped,
    }

    private struct Pending
    {
        Runnable command;
        ulong route;
    }

    private shared uint held;
    private Pending[] pending;
    private size_t head;
    private size_t tail;
    private size_t count;
    private size_t active;
    private Phase phase;

    private TaskFailureObserver observer;

    this(size_t capacity, TaskFailureObserver observer = null)
    {
        assert(capacity != 0);
        pending = new Pending[capacity];
        this.observer = observer;
    }

    // Publish must make one scalar mailbox post and return without waiting or
    // running a command. A consumer claims the identity under the same guard.
    Admission tryAdmit(Runnable command, scope bool delegate() @safe nothrow @nogc publish) nothrow @nogc
    {
        return tryAdmitTracked(command, (out ulong route) => publish());
    }

    Admission tryAdmitTracked(Runnable command, scope TrackedPost publish) nothrow @nogc
    {
        if (command is null)
            return Admission.invalidCommand;
        lock();
        scope (exit)
            unlock();
        if (phase != Phase.open)
            return Admission.closed;
        if (count == pending.length)
            return Admission.full;
        ulong route;
        if (!publish(route))
            return Admission.unavailable;
        pending[tail] = Pending(command, route);
        tail = advance(tail);
        ++count;
        return Admission.accepted;
    }

    // Called by a native worker immediately before running the command. A
    // queued offload waits here logically until the worker or shutdown wins.
    bool tryStart(ref ExecutorClaim claim) nothrow @nogc
    {
        assert(claim.owner is null);
        lock();
        scope (exit)
            unlock();
        if (count == 0)
            return false;
        claim.owner = this;
        claim.task = takePending();
        ++active;
        return true;
    }

    // Retire once, after the command and any offloaded operation have finished.
    void retire(ref ExecutorClaim claim) nothrow @nogc
    {
        assert(claim.owner is this);
        lock();
        scope (exit)
            unlock();
        assert(active != 0);
        claim.owner = null;
        claim.task = null;
        --active;
    }

    void reportFailure(Runnable command, ManagedOffloadResult result) nothrow @nogc
    {
        if (observer !is null && (result.error.code != Status.ok || result.failure !is null))
            observer(command, result.error, result.failure);
    }

    void shutdown() nothrow @nogc
    {
        lock();
        scope (exit)
            unlock();
        if (phase == Phase.open)
            phase = Phase.draining;
    }

    Runnable[] shutdownNow(scope void delegate(ulong) @safe nothrow @nogc revoke = null)
    {
        Pending[] detached;
        size_t start;
        size_t remaining;
        {
            lock();
            scope (exit)
                unlock();
            if (phase != Phase.stopped)
            {
                detached = pending;
                start = head;
                remaining = count;
                pending = null;
                count = 0;
                phase = Phase.stopped;
            }
        }
        if (remaining == 0)
            return null;

        // Release detached routes before allocating the result. The guard
        // is released, and a concurrent callback cannot claim a detached task.
        if (revoke !is null)
            foreach (index; 0 .. remaining)
                revoke(detached[(start + index) % detached.length].route);

        auto commands = new Runnable[remaining];
        foreach (ref command; commands)
        {
            command = detached[start++].command;
            if (start == detached.length)
                start = 0;
        }
        return commands;
    }

    bool isShutdown() nothrow @nogc
    {
        lock();
        scope (exit)
            unlock();
        return phase != Phase.open;
    }

    bool isTerminated() nothrow @nogc
    {
        lock();
        scope (exit)
            unlock();
        return phase != Phase.open && count == 0 && active == 0;
    }

    // All guarded work is bounded, performs no allocation and never yields
    // a fiber. Detached commands are copied after the guard is released.
    private void lock() nothrow @nogc
    {
        while (atomicLoad!(MemoryOrder.raw)(held) != 0 || !casWeak!(MemoryOrder.acq, MemoryOrder.raw)(&held, 0u, 1u))
            pause();
    }

    private void unlock() nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(held, 0u);
    }

    private size_t advance(size_t index) const pure nothrow @nogc
    {
        return index + 1 == pending.length ? 0 : index + 1;
    }

    private Runnable takePending() nothrow @nogc
    {
        auto command = pending[head].command;
        pending[head] = Pending.init;
        head = advance(head);
        --count;
        return command;
    }
}
