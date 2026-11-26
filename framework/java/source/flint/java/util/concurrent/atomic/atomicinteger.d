/** Java SE AtomicInteger, implemented from the API specification. */
module flint.java.util.concurrent.atomic.atomicinteger;

import core.atomic : atomicLoad, atomicOp, atomicStore;

@safe:

/// `java.util.concurrent.atomic.AtomicInteger`.
final class AtomicInteger
{
    private shared int value;

    /// An atomic integer starting at `initialValue`.
    this(int initialValue = 0) nothrow @nogc
    {
        atomicStore(value, initialValue);
    }

    /// Adds one and returns the new value.
    int incrementAndGet() nothrow @nogc
    {
        return atomicOp!"+="(value, 1);
    }

    /// Returns the value, then adds one.
    int getAndIncrement() nothrow @nogc
    {
        return atomicOp!"+="(value, 1) - 1;
    }

    /// The value.
    int get() nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// Sets the value.
    void set(int newValue) nothrow @nogc
    {
        atomicStore(value, newValue);
    }
}
