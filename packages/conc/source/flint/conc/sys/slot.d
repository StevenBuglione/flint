/// Atomic publication of a GC object reference through a `shared` slot.
module flint.conc.sys.slot;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, cas;

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
