// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.concurrent.internal.executorrouting;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, casWeak, pause;
import flint.java.lang.runnable : Runnable;
import flint.java.util.concurrent.internal.executoradmissions : Admission, ExecutorAdmissions;

@safe:

private alias ScalarPost = bool delegate(ulong) @safe nothrow @nogc;

// Each mailbox publication has a separate route. Tokens use a one-based
// slot in the low half and a nonzero, nonwrapping generation in the high half.
package(flint.java.util.concurrent) final class ExecutorRoutes
{
    private struct Slot
    {
        ExecutorAdmissions queue;
        uint generation;
        uint nextFree;
    }

    private shared uint held;
    private Slot[] slots;
    private uint free;

    this(uint capacity)
    {
        assert(capacity != 0);
        slots = new Slot[capacity];
        foreach (index, ref slot; slots)
            slot.nextFree = index + 1 < slots.length ? cast(uint)(index + 2) : 0;
        free = 1;
    }

    // Each queue publishes to one FIFO owner. The callback must post a scalar
    // without waiting or calling a claimant synchronously.
    Admission admit(ExecutorAdmissions queue, Runnable command, scope ScalarPost post) nothrow @nogc
    {
        return queue.tryAdmitTracked(command, (out ulong token) {
            token = reserve(queue);
            if (token == 0)
                return false;
            scope (failure)
                revoke(queue, token);
            if (post(token))
                return true;
            revoke(queue, token);
            return false;
        });
    }

    // Mailbox callbacks consume permits in FIFO order on the queue's sole
    // reactor owner. Native workers can take the oldest pending command in any
    // order after that. A started command's token has already been consumed.
    ExecutorAdmissions takePermit(ulong token) nothrow @nogc
    {
        const index = cast(uint) token;
        const generation = cast(uint)(token >> 32);
        if (index == 0 || index > slots.length || generation == 0)
            return null;
        lock();
        scope (exit)
            unlock();
        auto slot = &slots[index - 1];
        if (slot.generation != generation || slot.queue is null)
            return null;
        auto queue = slot.queue;
        release(*slot, index);
        return queue;
    }

    Runnable[] shutdownNow(ExecutorAdmissions queue)
    {
        return queue.shutdownNow((ulong token) => revoke(queue, token));
    }

    private ulong reserve(ExecutorAdmissions queue) nothrow @nogc
    {
        lock();
        scope (exit)
            unlock();
        if (free == 0)
            return 0;
        const index = free;
        auto slot = &slots[index - 1];
        free = slot.nextFree;
        slot.queue = queue;
        ++slot.generation;
        return (cast(ulong) slot.generation << 32) | index;
    }

    private void revoke(ExecutorAdmissions queue, ulong token) nothrow @nogc
    {
        const index = cast(uint) token;
        const generation = cast(uint)(token >> 32);
        if (index == 0 || index > slots.length || generation == 0)
            return;
        lock();
        scope (exit)
            unlock();
        auto slot = &slots[index - 1];
        if (slot.generation != generation || slot.queue !is queue)
            return;
        release(*slot, index);
    }

    private void release(ref Slot slot, uint index) nothrow @nogc
    {
        slot.queue = null;
        if (slot.generation != uint.max)
        {
            slot.nextFree = free;
            free = index;
        }
    }

    private void lock() nothrow @nogc
    {
        while (atomicLoad!(MemoryOrder.raw)(held) != 0 || !casWeak!(MemoryOrder.acq, MemoryOrder.raw)(&held, 0u, 1u))
            pause();
    }

    private void unlock() nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(held, 0u);
    }
}
