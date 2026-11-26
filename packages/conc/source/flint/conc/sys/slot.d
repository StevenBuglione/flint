/// Atomic publication of a GC object reference through a `shared` slot.
module flint.conc.sys.slot;

import core.atomic : MemoryOrder, atomicExchange, atomicLoad, atomicStore, cas;

@safe:

// The slot holds a GC reference, which the collector keeps alive while the slot does. The object's own
// synchronization is its contract, as for a Java static field.
// SAFETY: the acquire load pairs with the release store, so a reader sees the object fully constructed.
package(flint.conc) @trusted Object loadSlot(ref shared Object slot) nothrow @nogc
{
    return cast(Object) atomicLoad!(MemoryOrder.acq)(slot);
}

// SAFETY: a release store of a GC reference (or null); nothing is freed and no unshared data is retained here.
package(flint.conc) @trusted void storeSlot(ref shared Object slot, Object value) nothrow @nogc
{
    atomicStore!(MemoryOrder.rel)(slot, cast(shared) value);
}

// SAFETY: sequentially consistent compare-and-swap of GC references, which are compared and published only.
package(flint.conc) @trusted bool exchangeSlot(ref shared Object slot, Object expected, Object desired) nothrow @nogc
{
    return cas(&slot, cast(shared) expected, cast(shared) desired);
}

// SAFETY: the sequentially consistent load copies a GC reference from the live slot. The caller
// synchronizes the object's own state.
package(flint.conc) @trusted Object loadVolatileSlot(ref shared Object slot) nothrow @nogc
{
    return cast(Object) atomicLoad!(MemoryOrder.seq)(slot);
}

// SAFETY: the sequentially consistent store publishes a GC reference or null into the live slot.
package(flint.conc) @trusted void storeVolatileSlot(ref shared Object slot, Object value) nothrow @nogc
{
    atomicStore!(MemoryOrder.seq)(slot, cast(shared) value);
}

// SAFETY: the atomic exchange replaces a GC reference and returns its old value. The collector
// can see the reference in the slot and in the returned value.
package(flint.conc) @trusted Object replaceSlot(ref shared Object slot, Object value) nothrow @nogc
{
    return cast(Object) atomicExchange!(MemoryOrder.seq)(&slot, cast(shared) value);
}

// SAFETY: the strong CAS only compares and copies GC references. The witness belongs to this call
// and holds the reference observed at the same atomic operation that attempts publication.
package(flint.conc) @trusted Object casWitness(ref shared Object slot, Object expected, Object desired) nothrow @nogc
{
    shared Object witness = cast(shared) expected;
    cas(&slot, &witness, cast(shared) desired);
    return cast(Object) witness;
}
