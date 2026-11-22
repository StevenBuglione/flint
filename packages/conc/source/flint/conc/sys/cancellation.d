module flint.conc.sys.cancellation;

import core.atomic : MemoryOrder, atomicLoad, atomicOp, atomicStore;
import core.time : MonoTime;
import flint.arena : Status;
import flint.conc.sys.atomics : SpinLock;

@safe:

package(flint.conc) enum noDeadline = long.max;
package(flint.conc) enum closedContextId = ulong.max;
private enum slots = 16_384;
private enum slotBits = 15;
private enum slotMask = (1UL << slotBits) - 1;
private enum maxGeneration = ulong.max >> slotBits;

// Every holder of a context or source owns one counted reference. A referenced node keeps its
// generation and parent until the final release, and so does each ancestor, because a child holds
// a reference to its parent. Only `references` and `cancelledAt` change while a node is referenced;
// they are accessed atomically, so retain, release and status checks run without the slab lock.
// The lock serializes slot allocation, the free list, `open` and the single cancellation store.
// One cache line per node keeps reference counts of contexts used on different cores apart.
private align(64) struct Node
{
    ulong generation;
    ulong parent;
    shared ulong references;
    // A slot has no live deadline before createSource initializes it. Keep
    // unused slab storage zero-initialized so it can reside in BSS.
    long deadline;
    shared long cancelledAt;
    uint nextFree;
    bool open;
}

private struct Slab
{
    Node[slots] nodes;
    uint freeHead;
    uint allocated;

    ref Node get(ulong id) return nothrow @nogc
    {
        immutable slot = cast(uint)(id & slotMask);
        assert(slot > 0 && slot <= allocated);
        ref Node node = nodes[slot - 1];
        assert(node.generation == id >> slotBits && atomicLoad!(MemoryOrder.raw)(node.references) != 0);
        return node;
    }
}

private __gshared Slab slab;
private __gshared SpinLock slabLock;

package(flint.conc) long monotonicNanoseconds() nothrow @nogc
{
    return (MonoTime.currTime - MonoTime.zero).total!"nsecs";
}

// SAFETY: The slab stays at one process-wide address. The lock protects every
// access, and the scoped callback can only borrow the slab during this call.
private R locked(R)(scope R delegate(ref scope Slab) @safe nothrow @nogc operation) @trusted nothrow @nogc
{
    slabLock.lock();
    scope (exit)
        slabLock.unlock();
    return operation(slab);
}

// Callers read only the fixed generation and parent fields and touch the shared fields through core.atomic.
// SAFETY: The caller holds a counted reference to `id` or to a descendant, so this node stays allocated
// and its generation and parent stay fixed while the returned reference is used.
private ref Node referenced(ulong id) @trusted nothrow @nogc
{
    immutable slot = cast(uint)(id & slotMask);
    assert(slot != 0);
    ref Node node = slab.nodes[slot - 1];
    assert(node.generation == id >> slotBits);
    return node;
}

package(flint.conc) ulong createSource(ulong parent, long deadline) nothrow @nogc
{
    return locked!ulong((ref scope Slab state) {
        if (state.freeHead == 0 && state.allocated == slots)
            return 0UL;

        uint slot;
        if (state.freeHead != 0)
        {
            slot = state.freeHead;
            state.freeHead = state.nodes[slot - 1].nextFree;
        }
        else
        {
            slot = ++state.allocated;
        }

        ref Node node = state.nodes[slot - 1];
        ++node.generation;
        node.open = true;
        node.parent = parent;
        node.deadline = deadline;
        atomicStore!(MemoryOrder.raw)(node.cancelledAt, noDeadline);
        atomicStore!(MemoryOrder.raw)(node.references, 1UL);
        if (parent != 0 && parent != closedContextId)
            atomicOp!"+="(state.get(parent).references, 1UL);
        return (node.generation << slotBits) | slot;
    });
}

package(flint.conc) bool retainFromSource(ulong id) nothrow @nogc
{
    return locked!bool((ref scope Slab state) {
        immutable slot = cast(uint)(id & slotMask);
        if (slot == 0 || slot > state.allocated)
            return false;
        ref Node node = state.nodes[slot - 1];
        if (node.generation != id >> slotBits || !node.open)
            return false;
        // An open source owns a reference, so the count cannot reach zero concurrently.
        atomicOp!"+="(node.references, 1UL);
        return true;
    });
}

package(flint.conc) void retainContext(ulong id) nothrow @nogc
{
    if (id == 0 || id == closedContextId)
        return;
    const count = atomicOp!"+="(referenced(id).references, 1UL);
    assert(count > 1);
}

// Return a node whose final reference was just dropped to the free list, then release its parent.
private void retire(ref scope Slab state, ulong id) nothrow @nogc
{
    for (;;)
    {
        ref Node node = state.nodes[cast(uint)(id & slotMask) - 1];
        // Retire a slot permanently before generation wrap can alias any ID.
        if (node.generation < maxGeneration)
        {
            node.nextFree = state.freeHead;
            state.freeHead = cast(uint)(id & slotMask);
        }
        id = node.parent;
        if (id == 0 || id == closedContextId || atomicOp!"-="(state.get(id).references, 1UL) != 0)
            return;
    }
}

private void release(ref scope Slab state, ulong id) nothrow @nogc
{
    if (id != 0 && id != closedContextId && atomicOp!"-="(state.get(id).references, 1UL) == 0)
        retire(state, id);
}

package(flint.conc) void releaseContext(ulong id) nothrow @nogc
{
    if (id == 0 || id == closedContextId)
        return;
    // Only the final holder takes the lock; nobody else can reach a node without a reference.
    if (atomicOp!"-="(referenced(id).references, 1UL) == 0)
        locked!void((ref scope Slab state) { retire(state, id); });
}

package(flint.conc) void closeSource(ulong id) nothrow @nogc
{
    locked!void((ref scope Slab state) {
        immutable slot = cast(uint)(id & slotMask);
        if (slot == 0 || slot > state.allocated)
            return;
        ref Node node = state.nodes[slot - 1];
        if (node.generation != id >> slotBits || !node.open)
            return;
        node.open = false;
        release(state, id);
    });
}

package(flint.conc) void cancelSource(ulong id) nothrow @nogc
{
    locked!void((ref scope Slab state) {
        immutable slot = cast(uint)(id & slotMask);
        if (slot == 0 || slot > state.allocated)
            return;
        ref Node node = state.nodes[slot - 1];
        if (node.generation != id >> slotBits || !node.open
            || atomicLoad!(MemoryOrder.raw)(node.cancelledAt) != noDeadline)
            return;

        immutable now = monotonicNanoseconds();
        if (now < node.deadline)
            atomicStore!(MemoryOrder.rel)(node.cancelledAt, now);
    });
}

// A child has the earliest inherited deadline. An ancestor's explicit
// cancellation wins only when it happened before that deadline. Each
// cancellation time is written once, so this walk linearizes at its first load.
private bool cancelledBefore(ulong id, long deadline) nothrow @nogc
{
    for (ulong current = id; current != 0;)
    {
        if (current == closedContextId)
            return true;
        ref Node node = referenced(current);
        if (atomicLoad!(MemoryOrder.acq)(node.cancelledAt) < deadline)
            return true;
        current = node.parent;
    }
    return false;
}

package(flint.conc) Status contextStatus(ulong id, long deadline) nothrow @nogc
{
    if (cancelledBefore(id, deadline))
        return Status.cancelled;
    return deadline != noDeadline && monotonicNanoseconds() >= deadline ? Status.timedOut : Status.ok;
}

/// Like contextStatus, judging the deadline against a monotonic sample the caller already took.
package(flint.conc) Status contextStatusAt(ulong id, long deadline, long now) nothrow @nogc
{
    if (cancelledBefore(id, deadline))
        return Status.cancelled;
    return deadline != noDeadline && now >= deadline ? Status.timedOut : Status.ok;
}
