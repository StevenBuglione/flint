// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Native fallback leaf. Keep imports independent of flint.java.lang so module initialization has no cycle.
module flint.java.nativethreadidentity;

@safe:

// One identity per native thread. A fiber provider replaces this fallback before fibers call currentThread;
// without it, all fibers on one native thread share this identity, as they share the thread. This is a
// reviewed thread root (policy/safety-policy.json), not per-task state.
private Object identity;

package(flint.java) Object nativeThreadIdentity(bool create, Object candidate) nothrow @nogc
{
    if (identity !is null || !create || candidate is null)
        return identity;
    identity = candidate;
    return identity;
}

// The identity a thread created by `Thread.start` runs under. Unlike `identity`, this is not a lazily created
// native-thread identity: it is written once by the spawner before the body runs, so every observer inside that
// thread sees the same `Thread` object the starter holds. A fiber provider still wins over it when it has an
// identity of its own.
private Object spawnedIdentity;

package(flint.java) Object spawnedThreadIdentity() nothrow @nogc
{
    return spawnedIdentity;
}

package(flint.java) void setSpawnedThreadIdentity(Object identity) nothrow @nogc
{
    spawnedIdentity = identity;
}
