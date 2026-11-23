/++
Interim stand-in for framework-core's `flint.java.util.concurrent.atomic`: `AtomicLong` (gs-rest-service's request
counter). Deleted when `flint:java` has it.
+/
module flint.java.util.concurrent.atomic;

import core.atomic : atomicLoad, atomicOp, atomicStore;

@safe:

/// `java.util.concurrent.atomic.AtomicLong`.
final class AtomicLong
{
    private shared long value;

    ///
    this(long initialValue = 0) nothrow @nogc
    {
        atomicStore(value, initialValue);
    }

    /// Adds one and returns the new value.
    long incrementAndGet() nothrow @nogc
    {
        return atomicOp!"+="(value, 1);
    }

    /// Returns the value, then adds one.
    long getAndIncrement() nothrow @nogc
    {
        return atomicOp!"+="(value, 1) - 1;
    }

    /// The value.
    long get() nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// Sets the value.
    void set(long newValue) nothrow @nogc
    {
        atomicStore(value, newValue);
    }
}
