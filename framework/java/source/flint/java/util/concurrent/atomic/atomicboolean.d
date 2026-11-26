/** Java SE 21 AtomicBoolean, implemented from the API specification. */
module flint.java.util.concurrent.atomic.atomicboolean;

import core.atomic : MemoryOrder, atomicExchange, atomicLoad, atomicStore, cas, casWeak;

@safe:

/// A boolean value with atomic read, write and conditional update operations (R1, R3).
final class AtomicBoolean
{
    private shared bool value;

    /// Creates a false flag, or starts at initialValue.
    this(bool initialValue = false) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, initialValue);
    }

    /// Reads the flag with volatile ordering.
    bool get() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// Reads the flag with the ordering needed before consuming published data.
    bool getAcquire() const nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.acq)(value);
    }

    /// Reads the flag with ordering local to the flag.
    bool getOpaque() const nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(value);
    }

    /// Reads the flag without an acquire barrier.
    bool getPlain() const nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(value);
    }

    /// Writes the flag with volatile ordering.
    void set(bool newValue) nothrow @nogc
    {
        atomicStore(value, newValue);
    }

    /// Publishes preceding writes when setting the flag.
    void setRelease(bool newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(value, newValue);
    }

    /// Sets the flag with release ordering.
    void lazySet(bool newValue) nothrow @nogc
    {
        setRelease(newValue);
    }

    /// Writes the flag with ordering local to the flag.
    void setOpaque(bool newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, newValue);
    }

    /// Writes the flag without a release barrier.
    void setPlain(bool newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, newValue);
    }

    /// Replaces the flag and returns its previous value.
    bool getAndSet(bool newValue) nothrow @nogc
    {
        return atomicExchange(&value, newValue);
    }

    /// Replaces the flag if it matches expectedValue and reports whether the update succeeded.
    bool compareAndSet(bool expectedValue, bool newValue) nothrow @nogc
    {
        return cas(&value, expectedValue, newValue);
    }

    /// Conditionally replaces the flag and returns the value observed at the comparison.
    bool compareAndExchange(bool expectedValue, bool newValue) nothrow @nogc
    {
        cas(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Conditionally replaces the flag and acquires the value observed at the comparison.
    bool compareAndExchangeAcquire(bool expectedValue, bool newValue) nothrow @nogc
    {
        cas!(MemoryOrder.acq, MemoryOrder.acq)(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Conditionally publishes the replacement and returns the value observed at the comparison.
    bool compareAndExchangeRelease(bool expectedValue, bool newValue) nothrow @nogc
    {
        cas!(MemoryOrder.rel, MemoryOrder.raw)(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Attempts a plain conditional update, which may fail even if the flag matches.
    bool weakCompareAndSetPlain(bool expectedValue, bool newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.raw, MemoryOrder.raw)(&value, expectedValue, newValue);
    }

    /// Attempts a plain conditional update.
    deprecated("Use weakCompareAndSetPlain for plain memory ordering.") bool weakCompareAndSet(
            bool expectedValue, bool newValue) nothrow @nogc
    {
        return weakCompareAndSetPlain(expectedValue, newValue);
    }

    /// Attempts a conditional update with acquire ordering.
    bool weakCompareAndSetAcquire(bool expectedValue, bool newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.acq, MemoryOrder.acq)(&value, expectedValue, newValue);
    }

    /// Attempts a conditional update with release ordering on success.
    bool weakCompareAndSetRelease(bool expectedValue, bool newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.rel, MemoryOrder.raw)(&value, expectedValue, newValue);
    }

    /// Attempts a conditional update with volatile ordering.
    bool weakCompareAndSetVolatile(bool expectedValue, bool newValue) nothrow @nogc
    {
        return casWeak(&value, expectedValue, newValue);
    }

    /// Returns the lower-case name of the current boolean.
    override string toString() const nothrow @nogc
    {
        return get() ? "true" : "false";
    }
}
