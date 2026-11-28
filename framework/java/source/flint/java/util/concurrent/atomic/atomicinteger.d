/** Java SE AtomicInteger, implemented from the API specification. */
module flint.java.util.concurrent.atomic.atomicinteger;

import core.atomic : MemoryOrder, atomicExchange, atomicLoad, atomicOp, atomicStore, cas, casWeak;
import flint.engine.aot.text : decimal;
import flint.java.util.function_ : IntBinaryOperator;

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

    /// Subtracts one and returns the new value.
    int decrementAndGet() nothrow @nogc
    {
        return atomicOp!"-="(value, 1);
    }

    /// Returns the value, then subtracts one.
    int getAndDecrement() nothrow @nogc
    {
        return atomicOp!"-="(value, 1) + 1;
    }

    /// Adds `delta` and returns the new value.
    int addAndGet(int delta) nothrow @nogc
    {
        return atomicOp!"+="(value, delta);
    }

    /// Returns the value, then adds `delta`.
    int getAndAdd(int delta) nothrow @nogc
    {
        return atomicOp!"+="(value, delta) - delta;
    }

    /// The value.
    int get() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// Reads the value with the ordering local to the value.
    int getOpaque() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(value);
    }

    /// Reads the value with acquire ordering.
    int getAcquire() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.acq)(value);
    }

    /// Reads the value without acquire ordering.
    int getPlain() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(value);
    }

    /// Sets the value.
    void set(int newValue) nothrow @nogc
    {
        atomicStore(value, newValue);
    }

    /// Sets the value with release ordering.
    void lazySet(int newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(value, newValue);
    }

    /// Sets the value with the ordering local to the value.
    void setOpaque(int newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, newValue);
    }

    /// Publishes preceding writes when setting the value.
    void setRelease(int newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(value, newValue);
    }

    /// Sets the value without release ordering.
    void setPlain(int newValue) nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(value, newValue);
    }

    /// Sets `newValue` and returns the previous value.
    int getAndSet(int newValue) nothrow @nogc
    {
        return atomicExchange(&value, newValue);
    }

    /// Sets `newValue` when the value is `expectedValue`; whether it did.
    bool compareAndSet(int expectedValue, int newValue) nothrow @nogc
    {
        return cas(&value, expectedValue, newValue);
    }

    /// Sets `newValue` when the value is `expectedValue`; the value observed at the comparison.
    int compareAndExchange(int expectedValue, int newValue) nothrow @nogc
    {
        cas(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Sets `newValue` when the value is `expectedValue`; the value observed with acquire ordering.
    int compareAndExchangeAcquire(int expectedValue, int newValue) nothrow @nogc
    {
        cas!(MemoryOrder.acq, MemoryOrder.acq)(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Sets `newValue` when the value is `expectedValue`; the value observed with release ordering.
    int compareAndExchangeRelease(int expectedValue, int newValue) nothrow @nogc
    {
        cas!(MemoryOrder.rel, MemoryOrder.raw)(&value, &expectedValue, newValue);
        return expectedValue;
    }

    /// Attempts a plain conditional update, which may fail even if the value matches.
    bool weakCompareAndSetPlain(int expectedValue, int newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.raw, MemoryOrder.raw)(&value, expectedValue, newValue);
    }

    /// Attempts a plain conditional update.
    deprecated("Use weakCompareAndSetPlain for plain memory ordering.") bool weakCompareAndSet(
            int expectedValue, int newValue) nothrow @nogc
    {
        return weakCompareAndSetPlain(expectedValue, newValue);
    }

    /// Attempts a conditional update with acquire ordering.
    bool weakCompareAndSetAcquire(int expectedValue, int newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.acq, MemoryOrder.acq)(&value, expectedValue, newValue);
    }

    /// Attempts a conditional update with release ordering on success.
    bool weakCompareAndSetRelease(int expectedValue, int newValue) nothrow @nogc
    {
        return casWeak!(MemoryOrder.rel, MemoryOrder.raw)(&value, expectedValue, newValue);
    }

    /// Attempts a conditional update with volatile ordering.
    bool weakCompareAndSetVolatile(int expectedValue, int newValue) nothrow @nogc
    {
        return casWeak(&value, expectedValue, newValue);
    }

    /// Applies `updateFunction` to the current value, returning the previous value.
    int getAndAccumulate(int x, IntBinaryOperator accumulatorFunction)
    {
        int previous;
        do
            previous = get();
        while (!compareAndSet(previous, accumulatorFunction.applyAsInt(previous, x)));
        return previous;
    }

    /// Applies `accumulatorFunction` to the current value and `x`, returning the new value.
    int accumulateAndGet(int x, IntBinaryOperator accumulatorFunction)
    {
        int previous, next;
        do
        {
            previous = get();
            next = accumulatorFunction.applyAsInt(previous, x);
        }
        while (!compareAndSet(previous, next));
        return next;
    }

    /// The decimal value, as Java's `Integer.toString`.
    override string toString() const nothrow
    {
        return decimal(atomicLoad(value));
    }

    /// The value as an `int`.
    int intValue() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// The value as a `long`.
    long longValue() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// The value as a `float`.
    float floatValue() const nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// The value as a `double`.
    double doubleValue() const nothrow @nogc
    {
        return atomicLoad(value);
    }
}
