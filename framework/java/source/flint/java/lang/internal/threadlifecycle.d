/// Installable thread lifecycle primitives: spawn, join and interruptible sleep. `flint:java` never imports the
/// reactor or the OS thread API; `flint:java-sys` installs the native fallback, and a composition may replace it.
module flint.java.lang.internal.threadlifecycle;

import core.atomic : atomicLoad, cas;
import flint.java.lang.thread : Thread, ThreadState;

@safe:

/// Start `owner`'s body on a new logical thread seeded with `owner`'s identity. False when the thread could not
/// be created; the caller then reports `Thread.start`'s failure.
package(flint.java) alias ThreadSpawner = bool function(Thread, void delegate() @safe nothrow) @safe;

/// Wait until `target` finishes, `timeoutNanos` passes (zero waits indefinitely), or `waiter` is interrupted.
/// `waiter` may be null when the caller has no logical-thread identity.
package(flint.java) alias ThreadJoiner = void function(Thread, ThreadState, long) @safe nothrow;

/// Sleep the calling logical thread for `timeoutNanos`, returning early when `state` is interrupted. `state` may
/// be null when the caller has no logical-thread identity.
package(flint.java) alias ThreadSleeper = void function(ThreadState state, long timeoutNanos) @safe nothrow;

private shared ThreadSpawner spawner;
private shared ThreadJoiner joiner;
private shared ThreadSleeper sleeper;

/// Install the spawner before the first `Thread.start`. Repeating the same provider preserves the selection.
package(flint.java) bool installThreadSpawner(ThreadSpawner provider) nothrow @nogc
{
    if (provider is null)
        return false;
    return cas(&spawner, ThreadSpawner.init, provider) || atomicLoad(spawner) is provider;
}

/// Install the joiner before the first `Thread.join`. Repeating the same provider preserves the selection.
package(flint.java) bool installThreadJoiner(ThreadJoiner provider) nothrow @nogc
{
    if (provider is null)
        return false;
    return cas(&joiner, ThreadJoiner.init, provider) || atomicLoad(joiner) is provider;
}

/// Install the sleeper before the first `Thread.sleep`. Repeating the same provider preserves the selection.
package(flint.java) bool installThreadSleeper(ThreadSleeper provider) nothrow @nogc
{
    if (provider is null)
        return false;
    return cas(&sleeper, ThreadSleeper.init, provider) || atomicLoad(sleeper) is provider;
}

package(flint.java):

ThreadSpawner selectThreadSpawner(ThreadSpawner fallback) nothrow @nogc
{
    auto provider = atomicLoad(spawner);
    if (provider is null)
    {
        if (cas(&spawner, ThreadSpawner.init, fallback))
            provider = fallback;
        else
            provider = atomicLoad(spawner);
    }
    return provider;
}

ThreadJoiner selectThreadJoiner(ThreadJoiner fallback) nothrow @nogc
{
    auto provider = atomicLoad(joiner);
    if (provider is null)
    {
        if (cas(&joiner, ThreadJoiner.init, fallback))
            provider = fallback;
        else
            provider = atomicLoad(joiner);
    }
    return provider;
}

ThreadSleeper selectThreadSleeper(ThreadSleeper fallback) nothrow @nogc
{
    auto provider = atomicLoad(sleeper);
    if (provider is null)
    {
        if (cas(&sleeper, ThreadSleeper.init, fallback))
            provider = fallback;
        else
            provider = atomicLoad(sleeper);
    }
    return provider;
}
