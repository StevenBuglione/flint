// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Thread.java
/*
 * Copyright (c) 1994, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */
// Modified by the Flint authors: a logical thread is a reactor fiber or a native thread, the identity comes from
// an installable provider (native fallback in flint:java-sys, fiber in flint:java-fiber), and the interrupt state
// is a small cross-thread facade.
module flint.java.lang.thread;

import core.atomic : atomicExchange, atomicLoad, atomicOp, atomicStore, cas;
import core.sync.mutex : Mutex;
import flint.java.lang.runnable : Runnable;

@safe:

/++
A wait that an interrupt ends.

The code that parks installs one before its final flag check, then retires it after it wakes. `wake` runs at
most once per installed wait, on the thread that called `interrupt`, and must not throw, allocate or block. It
may run after the waiter retired the wait, so the waiter re-checks `ThreadState.isInterrupted` after waking.
The delegate's target must be GC-managed and outlive the copied delegate: a stale `wake` can run after the
waiter retired or re-armed its wait, so the target must never be a stack or struct waiter.
+/
package(flint.java) struct InterruptSink
{
    /// Ends the registered wait. Null when no wait is installed.
    void delegate() @safe nothrow @nogc wake;
}

/++
One logical thread's interrupt state. Java's `Thread.interrupt`, `isInterrupted` and `interrupted` read and
write it; `java.util.concurrent`'s synchronizers install a wait around a park.

The waiter's protocol, in this order:

1. `token = state.install(InterruptSink(&waiter.wake));`
2. `if (state.isInterrupted()) { state.retire(token); /* handle */ }`
3. park
4. `state.retire(token);`
5. `if (state.isInterrupted()) /* handle */`

An interrupt between steps 1 and 4 either finds the installed sink or is seen by the check at step 2 or 5.
+/
package(flint.java) final class ThreadState
{
    private shared bool interrupted_;
    private shared uint generation_;
    private Mutex gate;
    private ulong lastToken;
    private ulong activeToken;
    private InterruptSink sink;

    this()
    {
        gate = new Mutex;
    }

    /// Whether the flag is set, without clearing it. Java's `Thread.isInterrupted`.
    bool isInterrupted() nothrow @nogc
    {
        return atomicLoad(interrupted_);
    }

    /// Clear the flag and return its previous value. Java's static `Thread.interrupted`.
    bool clearInterrupted() nothrow @nogc
    {
        return atomicExchange(&interrupted_, false);
    }

    /// Set the flag, then end the installed wait, if any. Java's `Thread.interrupt`.
    void interrupt() nothrow @nogc
    {
        // Bump the word before reading the sink, so a waiter between its guard and its park sees the change.
        atomicOp!"+="(generation_, 1);
        atomicStore(interrupted_, true);
        gate.lock_nothrow();
        const pending = sink;
        gate.unlock_nothrow();
        if (pending.wake !is null)
            pending.wake();
    }

    /// The word `interrupt` bumps before it calls the installed `wake`. A native or fiber waiter reads it before
    /// its guarded condition and parks on it with the observed value, so an interrupt between the check and the
    /// park is not lost.
    package(flint.java) ref shared(uint) generation() nothrow @nogc
    {
        return generation_;
    }

    /// Install one wait. Returns its token, or zero when a wait is already installed.
    ulong install(InterruptSink candidate) nothrow @nogc
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (activeToken != 0)
            return 0;
        activeToken = ++lastToken;
        sink = candidate;
        return activeToken;
    }

    /// Retire the wait named by `token`; a stale or empty token changes nothing.
    bool retire(ulong token) nothrow @nogc
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (token == 0 || activeToken != token)
            return false;
        activeToken = 0;
        sink = InterruptSink.init;
        return true;
    }
}

/++
Java's `Thread` over a logical thread: a reactor task fiber when `flint:java-fiber` installs its identity
provider, and a native thread otherwise. `currentThread` returns the calling logical thread's one object.

`start` runs `run` on a new OS thread, as Java's platform-thread `Thread` does. `join` and `sleep` wait on the
calling logical thread's interrupt state, so `interrupt` ends them. The spawn, join and sleep primitives come
from an installable provider (`flint:java-sys` installs the native fallback); `flint:java` itself never
imports the reactor.
+/
class Thread
{
    /++ Java's thread lifecycle states. A logical thread this port cannot observe beyond its start and finish
    reports `NEW`, `RUNNABLE` or `TERMINATED`; the three waiting states are declared for API compatibility. +/
    enum State
    {
        NEW,
        RUNNABLE,
        BLOCKED,
        WAITING,
        TIMED_WAITING,
        TERMINATED,
    }

    /++ Receives an exception that escapes `run`. Java's `Thread.UncaughtExceptionHandler`. +/
    interface UncaughtExceptionHandler
    {
        /// Handle `error` thrown by `thread`'s `run`.
        void uncaughtException(Thread thread, Throwable error);
    }

    private ThreadState state_;
    private string name_;
    private long id_;
    private Runnable target_;
    private UncaughtExceptionHandler uncaughtHandler_;
    private Throwable uncaught_;
    private shared uint started_;
    private shared uint alive_;
    private shared uint joinGeneration_;

    /// A thread with no task; a subclass overrides `run`.
    this()
    {
        state_ = new ThreadState;
        id_ = atomicOp!"+="(nextThreadId, 1L) + 1;
        name_ = defaultName(id_);
    }

    /// A thread that runs `target.run()`; a null target runs nothing, as Java allows.
    this(Runnable target)
    {
        this();
        target_ = target;
    }

    /// A thread that runs `target.run()` and reports `name`; a null name keeps the default.
    this(Runnable target, string name)
    {
        this(target);
        if (name !is null)
            name_ = name;
    }

    /// The calling logical thread's `Thread`; the same object on every call from that logical thread.
    static Thread currentThread()
    {
        import flint.java.lang.internal.threadcontrol : selectThreadIdentityProvider;
        import flint.java.lang.sys.threadslot : threadSlot;
        import flint.java.nativethreadidentity : spawnedThreadIdentity;

        auto provider = selectThreadIdentityProvider(&nativeIdentity);
        auto existing = provider(false, null);
        if (existing is null)
            existing = spawnedThreadIdentity();
        if (existing !is null)
            return threadSlot!Thread(existing);
        return threadSlot!Thread(provider(true, new Thread()));
    }

    /// The calling logical thread's interrupt state without creating its `Thread`, or null when the logical
    /// thread has no identity yet. Allocates nothing, so a `java.util.concurrent` wait inside a reactor task
    /// can read it.
    package(flint.java) static ThreadState currentThreadState() nothrow @nogc
    {
        import flint.java.lang.internal.threadcontrol : selectThreadIdentityProvider;
        import flint.java.lang.sys.threadslot : threadSlot;
        import flint.java.nativethreadidentity : spawnedThreadIdentity;

        auto identity = selectThreadIdentityProvider(&nativeIdentity)(false, null);
        if (identity is null)
            identity = spawnedThreadIdentity();
        return identity is null ? null : threadSlot!Thread(identity).state_;
    }

    /// Java's `run`: run the target, if there is one. A subclass overrides this.
    void run()
    {
        if (target_ !is null)
            target_.run();
    }

    /// Start `run` on a new OS thread. Java's `start`: a second call, or a call after termination, throws
    /// `IllegalThreadStateException`.
    void start()()
    {
        import flint.java.lang.internal.threadlifecycle : selectThreadSpawner;

        if (!cas(&started_, 0u, 1u))
            throwIllegalThreadState();
        atomicStore(alive_, 1u);
        if (!selectThreadSpawner(&nativeSpawn!())(this, &dispatch!()))
        {
            atomicStore(alive_, 0u);
            atomicStore(started_, 0u);
            throwStartFailed();
        }
    }

    /// Whether the thread has started and has not finished `run`. Java's `isAlive`.
    final bool isAlive() nothrow @nogc
    {
        return atomicLoad(alive_) != 0;
    }

    /// The lifecycle state; see `State` for what this port can observe.
    final State getState() nothrow @nogc
    {
        if (atomicLoad(started_) == 0)
            return State.NEW;
        return atomicLoad(alive_) != 0 ? State.RUNNABLE : State.TERMINATED;
    }

    /// Wait until this thread finishes. Java's `join`: a timeout of zero waits indefinitely, and an interrupt of
    /// the calling thread throws `InterruptedException` after clearing its flag.
    void join()()
    {
        joinNanos(0);
    }

    /// Wait at most `millis` milliseconds for this thread to finish.
    void join()(long millis)
    {
        if (millis < 0)
            throwNegativeTimeout();
        joinNanos(millisToNanos(millis));
    }

    /// Wait at most `millis` milliseconds and `nanos` nanoseconds (0 to 999,999) for this thread to finish.
    void join()(long millis, int nanos)
    {
        if (millis < 0)
            throwNegativeTimeout();
        if (nanos < 0 || nanos > 999_999)
            throwNanosOutOfRange();
        joinNanos(addNanos(millisToNanos(millis), nanos));
    }

    /// Sleep the calling logical thread. Java's `sleep`: a negative duration is an `IllegalArgumentException`,
    /// and an interrupt throws `InterruptedException` after clearing the flag.
    static void sleep()(long millis)
    {
        if (millis < 0)
            throwNegativeTimeout();
        sleepNanos(millisToNanos(millis));
    }

    /// Sleep `millis` milliseconds and `nanos` nanoseconds (0 to 999,999).
    static void sleep()(long millis, int nanos)
    {
        if (millis < 0)
            throwNegativeTimeout();
        if (nanos < 0 || nanos > 999_999)
            throwNanosOutOfRange();
        sleepNanos(addNanos(millisToNanos(millis), nanos));
    }

    /// Set this logical thread's interrupt flag and end its installed wait, if any.
    void interrupt() nothrow @nogc
    {
        state_.interrupt();
    }

    /// Whether this logical thread's flag is set, without clearing it.
    bool isInterrupted() nothrow @nogc
    {
        return state_.isInterrupted();
    }

    /// Java's static `Thread.interrupted()`: the calling thread's flag, cleared.
    static bool interrupted()
    {
        return currentThread().state_.clearInterrupted();
    }

    /// This thread's own handler, or null to use the default. Java's `getUncaughtExceptionHandler`.
    final UncaughtExceptionHandler getUncaughtExceptionHandler() nothrow @nogc
    {
        return uncaughtHandler_;
    }

    /// Set this thread's handler. Java's `setUncaughtExceptionHandler`.
    final void setUncaughtExceptionHandler(UncaughtExceptionHandler handler) nothrow @nogc
    {
        uncaughtHandler_ = handler;
    }

    /// The process-wide handler used when a thread has none. Java's static getter.
    static UncaughtExceptionHandler getDefaultUncaughtExceptionHandler()() nothrow @nogc
    {
        import flint.java.lang.sys.threadglobals : getDefaultUncaughtExceptionHandler;

        return getDefaultUncaughtExceptionHandler();
    }

    /// Set the process-wide handler. Java's static setter. The pointer store is atomic on the supported targets
    /// and Java does not order this setting against a thread that reads it.
    static void setDefaultUncaughtExceptionHandler()(UncaughtExceptionHandler handler) nothrow @nogc
    {
        import flint.java.lang.sys.threadglobals : setDefaultUncaughtExceptionHandler;

        setDefaultUncaughtExceptionHandler(handler);
    }

    /// Java's `threadId()`.
    long threadId() pure nothrow @nogc
    {
        return id_;
    }

    /// Java's deprecated `getId()`, the same value as `threadId()`.
    long getId() pure nothrow @nogc
    {
        return id_;
    }

    /// The thread's name; `Thread-<id>` until `setName` changes it.
    string getName() pure nothrow @nogc
    {
        return name_;
    }

    /// Java's `setName`: a null name throws `NullPointerException`.
    void setName(string name)
    {
        if (name is null)
            throwNullPointerException();
        name_ = name;
    }

    /// The interrupt state, for `java.util.concurrent`'s park protocol.
    package(flint.java) ThreadState state() pure nothrow @nogc
    {
        return state_;
    }

    /// The word a `join` parks on: `markTerminated` bumps it and the joiner's interrupt wakes it.
    package(flint.java) ref shared(uint) joinWord() nothrow @nogc
    {
        return joinGeneration_;
    }

    /// The word `isAlive` reads and `markTerminated` clears; the native provider polls it while parking on
    /// `joinWord`.
    package(flint.java) ref shared(uint) aliveWord() nothrow @nogc
    {
        return alive_;
    }

    /// Record that `run` finished and wake every joiner. The provider calls this once, on the thread itself.
    package(flint.java) void markTerminated() nothrow @nogc
    {
        atomicStore(alive_, 0u);
        atomicOp!"+="(joinGeneration_, 1u);
    }

    /// The exception `run` threw that no handler took, or null. Flint has no `ThreadGroup` and no standard
    /// stream, so the default handler keeps it here instead of printing it.
    package(flint.java) Throwable uncaughtError() nothrow @nogc
    {
        return uncaught_;
    }

    // The provider's body: run the task, then hand any escaping exception to the handler.
    private void dispatch()() @safe nothrow
    {
        try
            run();
        catch (Exception error)
            dispatchUncaught!()(error);
    }

    private void dispatchUncaught()(Throwable error) @safe nothrow
    {
        uncaught_ = error;
        import flint.java.lang.sys.threadglobals : getDefaultUncaughtExceptionHandler;

        auto handler = uncaughtHandler_;
        if (handler is null)
            handler = getDefaultUncaughtExceptionHandler();
        if (handler is null)
            return;
        try
            handler.uncaughtException(this, error);
        catch (Exception)
        {
        }
    }

    private void joinNanos()(long nanos)
    {
        import flint.java.lang.internal.threadlifecycle : selectThreadJoiner;

        auto waiter = currentThreadState();
        if (waiter !is null && waiter.isInterrupted())
        {
            waiter.clearInterrupted();
            throwInterrupted();
        }
        selectThreadJoiner(&nativeJoin!())(this, waiter, nanos);
        if (waiter !is null && waiter.clearInterrupted())
            throwInterrupted();
    }

    private static void sleepNanos()(long nanos)
    {
        import flint.java.lang.internal.threadlifecycle : selectThreadSleeper;

        if (nanos == 0)
            return;
        auto state = currentThreadState();
        if (state is null)
        {
            selectThreadSleeper(&nativeSleep!())(null, nanos);
            return;
        }
        if (state.isInterrupted())
        {
            state.clearInterrupted();
            throwInterrupted();
        }
        selectThreadSleeper(&nativeSleep!())(state, nanos);
        if (state.clearInterrupted())
            throwInterrupted();
    }
}

// The native fallback adapters erase the Java types for `flint:java-sys`, which cannot import this package.
private bool nativeSpawn()(Thread owner, void delegate() @safe nothrow 
        body) @safe
{
    import flint.java.nativethreadlifecycle : spawn = nativeThreadSpawn;

    return spawn(owner, body, &owner.markTerminated, &owner.joinWord());
}

private void nativeJoin()(Thread target, ThreadState waiter, long timeoutNanos) @safe nothrow
{
    import flint.java.nativethreadlifecycle : InterruptWait, WakeDelegate, join = nativeThreadJoin;

    InterruptWait wait;
    if (waiter !is null)
        wait = InterruptWait(() => waiter.isInterrupted(), &waiter.generation(),
                (WakeDelegate wake) => waiter.install(InterruptSink(wake)), (ulong token) => waiter.retire(token));
    join(&target.aliveWord(), &target.joinWord(), timeoutNanos, wait);
}

private void nativeSleep()(ThreadState state, long timeoutNanos) @safe nothrow
{
    import flint.java.nativethreadlifecycle : InterruptWait, WakeDelegate, sleep = nativeThreadSleep;

    InterruptWait wait;
    if (state !is null)
        wait = InterruptWait(() => state.isInterrupted(), &state.generation(),
                (WakeDelegate wake) => state.install(InterruptSink(wake)), (ulong token) => state.retire(token));
    sleep(wait, timeoutNanos);
}

private static long millisToNanos(long millis) pure nothrow @nogc
{
    return millis > long.max / 1_000_000 ? long.max : millis * 1_000_000;
}

private static long addNanos(long base, int nanos) pure nothrow @nogc
{
    return base > long.max - nanos ? long.max : base + nanos;
}

// The native fallback: flint:java-sys keeps one identity per native thread. A fiber provider installed by
// flint:java-fiber replaces it before any fiber calls currentThread.
private Object nativeIdentity(bool create, Object candidate) @safe nothrow @nogc
{
    import flint.java.nativethreadidentity : nativeThreadIdentity;

    return nativeThreadIdentity(create, candidate);
}

private shared long nextThreadId;

private string defaultName(long id)
{
    char[20] digits;
    size_t start = digits.length;
    ulong value = cast(ulong) id;
    do
    {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value);
    return "Thread-" ~ digits[start .. $].idup;
}

private noreturn throwNullPointerException()
{
    pragma(inline, false);
    import flint.java.lang : NullPointerException;

    throw new NullPointerException();
}

private noreturn throwIllegalThreadState()()
{
    pragma(inline, false);
    import flint.java.lang.runtimeexception : IllegalStateException;

    throw new IllegalStateException();
}

private noreturn throwInterrupted()()
{
    pragma(inline, false);
    import flint.java.lang.interruptedexception : InterruptedException;

    throw new InterruptedException();
}

private noreturn throwNegativeTimeout()()
{
    pragma(inline, false);
    import flint.java.lang.runtimeexception : IllegalArgumentException;

    throw new IllegalArgumentException("timeout value is negative");
}

private noreturn throwNanosOutOfRange()()
{
    pragma(inline, false);
    import flint.java.lang.runtimeexception : IllegalArgumentException;

    throw new IllegalArgumentException("nanosecond timeout value out of range");
}

private noreturn throwStartFailed()()
{
    pragma(inline, false);
    import flint.java.lang.runtimeexception : IllegalStateException;

    throw new IllegalStateException("unable to create native thread");
}
