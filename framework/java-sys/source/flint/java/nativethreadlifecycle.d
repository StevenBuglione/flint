// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Native fallback for `flint.java.lang.thread`'s lifecycle: an OS thread per `Thread.start`, and interruptible
/// join and sleep over `flint.conc.park`. The erased contracts keep this leaf independent of `flint:java`, which
/// depends on this package; `flint:java` adapts its `Thread` and `ThreadState` at the call sites.
module flint.java.nativethreadlifecycle;

import core.atomic : atomicLoad;
import core.thread.osthread : OSThread = Thread;
import core.time : MonoTime;
import flint.conc.park : park, wakeAll;
import flint.java.nativethreadidentity : setSpawnedThreadIdentity;

@safe:

/// Ends a parked wait: the delegate `ThreadState.install` stores.
package(flint.java) alias WakeDelegate = void delegate() @safe nothrow @nogc;

/// The erased interrupt state a native wait observes. A null `interrupted` means the caller has no state and the
/// wait is not interruptible.
package(flint.java) struct InterruptWait
{
    bool delegate() @safe nothrow @nogc interrupted;
    shared(uint)* generation;
    ulong delegate(WakeDelegate wake) @safe nothrow @nogc install;
    bool delegate(ulong token) @safe nothrow @nogc retire;
}

/// Start `body` on a new OS thread under `owner`'s identity. `onFinish` records termination and `joinWord` is the
/// word joiners park on; the wrapper runs `onFinish`, then wakes every joiner.
package(flint.java) bool nativeThreadSpawn(Object owner, void delegate() @safe nothrow 
        body,
        void delegate() @safe nothrow onFinish, shared(uint)* joinWord) @safe
{
    if (body is null || onFinish is null || joinWord is null)
        return false;

    void delegate() seeded = () {
        setSpawnedThreadIdentity(owner);
        scope (exit)
        {
            setSpawnedThreadIdentity(null);
            onFinish();
            wakeAll(*joinWord);
        }
        body();
    };

    return startNativeThread(new OSThread(seeded));
}

/// Wait until `alive` clears, `timeoutNanos` passes (zero waits indefinitely), or `waiter` is interrupted.
package(flint.java) void nativeThreadJoin(shared(uint)* alive, shared(uint)* joinWord,
        long timeoutNanos, InterruptWait waiter) @safe nothrow
{
    if (alive is null || joinWord is null || atomicLoad(*alive) == 0)
        return;

    const started = MonoTime.currTime.ticks;
    uint observed = atomicLoad(*joinWord);
    JoinWake wake;
    ulong token;
    if (waiter.interrupted !is null)
    {
        wake = new JoinWake(joinWord);
        const guard = atomicLoad(*waiter.generation);
        if (waiter.interrupted())
            return;
        token = waiter.install(&wake.wake);
        if (atomicLoad(*waiter.generation) != guard || waiter.interrupted())
        {
            if (token != 0)
                waiter.retire(token);
            return;
        }
    }
    scope (exit)
        if (token != 0)
            waiter.retire(token);

    while (atomicLoad(*alive) != 0)
    {
        const left = timeoutNanos == 0 ? long.max : timeoutNanos - elapsedNanos(started);
        if (left <= 0)
            return;
        park(*joinWord, observed, left);
        observed = atomicLoad(*joinWord);
        if (waiter.interrupted !is null && waiter.interrupted())
            return;
    }
}

/// Sleep the calling thread for `timeoutNanos`, returning early when `waiter` is interrupted.
package(flint.java) void nativeThreadSleep(InterruptWait waiter, long timeoutNanos) @safe nothrow
{
    if (timeoutNanos <= 0)
        return;

    const started = MonoTime.currTime.ticks;
    if (waiter.interrupted is null)
    {
        shared uint never;
        while (true)
        {
            const left = timeoutNanos - elapsedNanos(started);
            if (left <= 0)
                return;
            park(never, 0, left);
        }
    }

    uint observed = atomicLoad(*waiter.generation);
    if (waiter.interrupted())
        return;
    auto wake = new GenerationWake(waiter.generation);
    const token = waiter.install(&wake.wake);
    if (atomicLoad(*waiter.generation) != observed || waiter.interrupted())
    {
        if (token != 0)
            waiter.retire(token);
        return;
    }
    scope (exit)
        if (token != 0)
            waiter.retire(token);

    while (true)
    {
        const left = timeoutNanos - elapsedNanos(started);
        if (left <= 0)
            return;
        park(*waiter.generation, observed, left);
        observed = atomicLoad(*waiter.generation);
        if (waiter.interrupted())
            return;
    }
}

// `MonoTime.ticks` counts 100 ns units.
private long elapsedNanos(long startedTicks) @safe nothrow @nogc
{
    return (MonoTime.currTime.ticks - startedTicks) * 100;
}

private final class JoinWake
{
    private shared(uint)* word;

    this(shared(uint)* word) @safe nothrow @nogc
    {
        this.word = word;
    }

    void wake() @safe nothrow @nogc
    {
        wakeAll(*word);
    }
}

private final class GenerationWake
{
    private shared(uint)* word;

    this(shared(uint)* word) @safe nothrow @nogc
    {
        this.word = word;
    }

    void wake() @safe nothrow @nogc
    {
        wakeAll(*word);
    }
}

// SAFETY: `start` begins the delegate given at construction on a new OS thread and registers that thread with
// druntime. It receives no borrowed storage from this call and retains no reference to it.
@trusted private bool startNativeThread(OSThread thread) nothrow
{
    thread.start();
    return true;
}
