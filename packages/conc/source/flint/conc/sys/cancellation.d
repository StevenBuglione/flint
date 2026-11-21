module flint.conc.sys.cancellation;

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

private struct Node
{
    ulong generation;
    ulong parent;
    ulong references;
    // A slot has no live deadline before createSource initializes it. Keep
    // unused slab storage zero-initialized so it can reside in BSS.
    long deadline;
    long cancelledAt;
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
        assert(node.generation == id >> slotBits && node.references != 0);
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
        node.cancelledAt = noDeadline;
        node.references = 1;
        if (parent != 0 && parent != closedContextId)
            ++state.get(parent).references;
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
        ++node.references;
        return true;
    });
}

package(flint.conc) void retainContext(ulong id) nothrow @nogc
{
    if (id != 0 && id != closedContextId)
        locked!void((ref scope Slab state) { ++state.get(id).references; });
}

private void release(ref scope Slab state, ulong id) nothrow @nogc
{
    while (id != 0 && id != closedContextId)
    {
        ref Node node = state.get(id);
        assert(node.references != 0);
        if (--node.references != 0)
            return;

        // Retire a slot permanently before generation wrap can alias any ID.
        if (node.generation < maxGeneration)
        {
            node.nextFree = state.freeHead;
            state.freeHead = cast(uint)(id & slotMask);
        }
        id = node.parent;
    }
}

package(flint.conc) void releaseContext(ulong id) nothrow @nogc
{
    if (id != 0 && id != closedContextId)
        locked!void((ref scope Slab state) { release(state, id); });
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
        if (node.generation != id >> slotBits || !node.open || node.cancelledAt != noDeadline)
            return;

        immutable now = monotonicNanoseconds();
        if (now < node.deadline)
            node.cancelledAt = now;
    });
}

package(flint.conc) Status contextStatus(ulong id, long deadline) nothrow @nogc
{
    if (id == 0 && deadline == noDeadline)
        return Status.ok;

    return locked!Status((ref scope Slab state) {
        // A child has the earliest inherited deadline. An ancestor's explicit
        // cancellation wins only when it happened before that deadline.
        for (ulong current = id; current != 0;)
        {
            if (current == closedContextId)
                return Status.cancelled;
            ref const Node node = state.get(current);
            if (node.cancelledAt < deadline)
                return Status.cancelled;
            current = node.parent;
        }
        return deadline != noDeadline && monotonicNanoseconds() >= deadline ? Status.timedOut : Status.ok;
    });
}
