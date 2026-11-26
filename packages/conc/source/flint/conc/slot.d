/// A process-wide slot holding one object reference, published safely to every thread.
module flint.conc.slot;

import flint.conc.sys.slot : casWitness, exchangeSlot, loadSlot, loadVolatileSlot, replaceSlot,
    storeSlot, storeVolatileSlot;

@safe:

/**
 * One D class or interface reference shared by every thread and fiber: what a Java `static` field
 * holding a thread-safe object is. Declare it `shared` at module level; `get` sees the reference a
 * `set` or `setIfAbsent` published, with the object fully constructed. The slot synchronizes only the
 * reference: the object guards its own state, as Java's `LoggerFactory` provider does.
 */
struct ProcessSlot(T) if (is(T == class) || (is(T == interface) && is(typeof(T.init.classinfo))))
{
    private Object value;

    /// The published reference, or null.
    T get() shared nothrow @nogc
    {
        return cast(T) loadSlot(value);
    }

    /// Publish `reference`, replacing any earlier one.
    void set(T reference) shared nothrow @nogc
    {
        storeSlot(value, cast(Object) reference);
    }

    /// Publish `reference` unless one is already there; return whichever the slot holds afterwards.
    T setIfAbsent(T reference) shared nothrow @nogc
    {
        if (exchangeSlot(value, null, cast(Object) reference))
            return reference;
        return get();
    }

    /// Load the published reference in the sequentially consistent order.
    T getVolatile() shared nothrow @nogc
    {
        return cast(T) loadVolatileSlot(value);
    }

    /// Publish a reference in the sequentially consistent order.
    void setVolatile(T reference) shared nothrow @nogc
    {
        storeVolatileSlot(value, cast(Object) reference);
    }

    /// Replace the reference if it has the expected identity.
    bool compareAndSet(T expected, T desired) shared nothrow @nogc
    {
        return exchangeSlot(value, cast(Object) expected, cast(Object) desired);
    }

    /// Attempt replacement and return the reference observed at the comparison.
    T compareAndExchange(T expected, T desired) shared nothrow @nogc
    {
        return cast(T) casWitness(value, cast(Object) expected, cast(Object) desired);
    }

    /// Publish a reference and return the previous reference.
    T getAndSet(T reference) shared nothrow @nogc
    {
        return cast(T) replaceSlot(value, cast(Object) reference);
    }
}

private interface Greeter
{
    string greet();
}

private final class English : Greeter
{
    string greet()
    {
        return "hello";
    }
}

private shared ProcessSlot!Greeter testSlot;

@("ProcessSlot publishes once with setIfAbsent and replaces with set")
unittest
{
    assert(testSlot.get() is null);
    auto first = new English();
    assert(testSlot.setIfAbsent(first) is first);
    auto second = new English();
    assert(testSlot.setIfAbsent(second) is first, "a second setIfAbsent must not replace the first");
    assert(testSlot.get().greet() == "hello");
    testSlot.set(second);
    assert(testSlot.get() is second);
    testSlot.set(null);
    assert(testSlot.get() is null);
}
