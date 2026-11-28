/** Java SE AtomicLong, implemented from the API specification. */
module flint.java.util.concurrent.atomic.atomiclong;

import core.atomic : MemoryOrder, atomicExchange, atomicLoad, atomicOp, atomicStore, cas, casWeak;
import flint.engine.aot.text : decimal;

@safe:

/// `java.util.concurrent.atomic.AtomicLong`.
final class AtomicLong
{
    private shared long value;

    /// An atomic long starting at `initialValue`.
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
    long get() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// Reads the value with the ordering local to the value.
    long getOpaque() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(value);
    }

    /// Reads the value with acquire ordering.
    long getAcquire() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.acq)(value);
    }

    /// Reads the value without acquire ordering.
    long getPlain() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(value);
    }

    /// Sets the value.
    void set(long newValue) nothrow @nogc
    {
        atomicStore(value, newValue);
    }

    /// Sets the value with release ordering.
    void lazySet(long newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(value, newValue);
    }

    /// Sets the value with the ordering local to the value.
    void setOpaque(long newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, newValue);
    }

    /// Publishes preceding writes when setting the value.
    void setRelease(long newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(value, newValue);
    }

    /// Sets the value without release ordering.
    void setPlain(long newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, newValue);
    }

    /// Subtracts one and returns the new value.
    long decrementAndGet() nothrow @nogc
    {
        return atomicOp!"-="(value, 1);
    }

    /// Returns the value, then subtracts one.
    long getAndDecrement() nothrow @nogc
    {
        return atomicOp!"-="(value, 1) + 1;
    }

    /// Adds `delta` and returns the new value.
    long addAndGet(long delta) nothrow @nogc
    {
        return atomicOp!"+="(value, delta);
    }

    /// Returns the value, then adds `delta`.
    long getAndAdd(long delta) nothrow @nogc
    {
        return atomicOp!"+="(value, delta) - delta;
    }

    /// Sets `newValue` and returns the previous value.
    long getAndSet(long newValue) nothrow @nogc
    {
        return atomicExchange(&value, newValue);
    }

    /// Sets `newValue` when the value is `expectedValue`; whether it did.
    bool compareAndSet(long expectedValue, long newValue) nothrow @nogc
    {
        return cas(&value, expectedValue, newValue);
    }

    /// Sets `newValue` when the value is `expectedValue`; the value observed at the comparison.
    long compareAndExchange(long expectedValue, long newValue) nothrow @nogc
    {
        cas(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Sets `newValue` when the value is `expectedValue`; the value observed with acquire ordering.
    long compareAndExchangeAcquire(long expectedValue, long newValue) nothrow @nogc
    {
        cas!(MemoryOrder.acq, MemoryOrder.acq)(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Sets `newValue` when the value is `expectedValue`; the value observed with release ordering.
    long compareAndExchangeRelease(long expectedValue, long newValue) nothrow @nogc
    {
        cas!(MemoryOrder.rel, MemoryOrder.raw)(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Attempts a plain conditional update, which may fail even if the value matches.
    bool weakCompareAndSetPlain(long expectedValue, long newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.raw, MemoryOrder.raw)(&value, expectedValue, newValue);
    }

    /// Attempts a plain conditional update.
    deprecated("Use weakCompareAndSetPlain for plain memory ordering.") bool weakCompareAndSet(
            long expectedValue, long newValue) nothrow @nogc
    {
        return weakCompareAndSetPlain(expectedValue, newValue);
    }

    /// Attempts a conditional update with acquire ordering.
    bool weakCompareAndSetAcquire(long expectedValue, long newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.acq, MemoryOrder.acq)(&value, expectedValue, newValue);
    }

    /// Attempts a conditional update with release ordering on success.
    bool weakCompareAndSetRelease(long expectedValue, long newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.rel, MemoryOrder.raw)(&value, expectedValue, newValue);
    }

    /// Attempts a conditional update with volatile ordering.
    bool weakCompareAndSetVolatile(long expectedValue, long newValue) nothrow @nogc
    {
        return casWeak(&value, expectedValue, newValue);
    }

    /// The decimal value.
    override string toString() const nothrow
    {
        return decimal(atomicLoad(value));
    }

    /// The value as an `int`.
    int intValue() const nothrow @nogc
    {
        return cast(int) atomicLoad(value);
    }

    /// The value as a `long`.
    long longValue() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// The value as a `float`.
    float floatValue() const nothrow @nogc
    {
        return cast(float) atomicLoad(value);
    }

    /// The value as a `double`.
    double doubleValue() const nothrow @nogc
    {
        return cast(double) atomicLoad(value);
    }
}
