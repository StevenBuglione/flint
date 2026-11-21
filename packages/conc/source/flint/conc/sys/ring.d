module flint.conc.sys.ring;

import core.atomic : MemoryOrder, atomicLoad, atomicStore;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import flint.arena : Error, Result, Status;
import flint.conc.internal.transfer : TransferValue;
import flint.conc.sys.atomics : SpinLock;

@safe:

private struct Cell(T, Counter)
{
    shared Counter sequence;
    ubyte[T.sizeof] payload;
}

private struct Cursor(Counter)
{
    Counter position;
    ubyte[64 - Counter.sizeof] padding;
}

package(flint.conc) struct SequenceRing(T, bool multiConsumer, Counter = ulong) if (TransferValue!T)
{
    private Cell!(T, Counter)[] cells;
    private size_t mask;
    private shared bool closed;
    private SpinLock producerLock;
    static if (multiConsumer)
    {
        private SpinLock consumerLock;
    }
    private Cursor!Counter producer;
    private Cursor!Counter consumer;

    @disable this(this);

    ~this() nothrow @nogc
    {
        if (cells.length != 0)
            releaseCells(cells);
    }

    Status initialize(size_t capacity, Counter initial = 0) nothrow @nogc
    {
        assert(cells.length == 0);
        if (capacity < 2 || capacity > 1_048_576 || capacity > Counter.max / 2 || (capacity & (capacity - 1)) != 0)
            return Status.invalidArgument;
        if (capacity > size_t.max / Cell!(T, Counter).sizeof)
            return Status.outOfMemory;

        cells = allocateCells!(T, Counter)(capacity);
        if (cells.length == 0)
            return Status.outOfMemory;

        mask = capacity - 1;
        producer.position = initial;
        consumer.position = initial;
        foreach (i; 0 .. capacity)
        {
            immutable position = cast(Counter)(initial + i);
            atomicStore!(MemoryOrder.raw)(cells[position & mask].sequence, position);
        }
        return Status.ok;
    }

    Status send(T value) nothrow @nogc
    {
        if (cells.length == 0)
            return Status.cancelled;

        producerLock.lock();
        scope (exit)
            producerLock.unlock();

        if (atomicLoad!(MemoryOrder.raw)(closed))
            return Status.cancelled;

        immutable pos = producer.position;
        auto ref cell = cells[pos & mask];
        if (atomicLoad!(MemoryOrder.acq)(cell.sequence) != pos)
            return Status.resourceExhausted;

        storePayload(cell, value);
        producer.position = cast(Counter)(pos + 1);
        // Publication linearizes send. Serial reservation/publication prevents
        // a later successful send from appearing behind an unpublished cell.
        atomicStore!(MemoryOrder.rel)(cell.sequence, producer.position);
        return Status.ok;
    }

    Result!T receive() nothrow @nogc
    {
        if (cells.length == 0)
            return Result!T(T.init, Error(Status.cancelled, "channel closed"));

        static if (multiConsumer)
        {
            consumerLock.lock();
            scope (exit)
                consumerLock.unlock();
        }

        immutable pos = consumer.position;
        immutable published = cast(Counter)(pos + 1);
        auto ref cell = cells[pos & mask];
        if (atomicLoad!(MemoryOrder.acq)(cell.sequence) != published)
        {
            if (!atomicLoad!(MemoryOrder.acq)(closed))
                return Result!T(T.init, Error(Status.unavailable, "channel empty"));
            // Close acquires the producer gate, so re-reading after observing it
            // includes every publication preceding close.
            if (atomicLoad!(MemoryOrder.acq)(cell.sequence) != published)
                return Result!T(T.init, Error(Status.cancelled, "channel closed"));
        }

        T value = loadPayload(cell);
        consumer.position = published;
        // Recycling linearizes receive. The producer may reuse the cell only
        // after these reads finish. Equality checks remain valid across wrap
        // because the capacity is a power of two below half the counter range.
        atomicStore!(MemoryOrder.rel)(cell.sequence, cast(Counter)(pos + cells.length));
        return Result!T(value);
    }

    void close() nothrow @nogc
    {
        producerLock.lock();
        atomicStore!(MemoryOrder.rel)(closed, true);
        producerLock.unlock();
    }
}

// SAFETY: The caller checked the multiplication. malloc provides alignment for
// the scalar counter and byte-only payload; the ring initializes all counters.
private Cell!(T, Counter)[] allocateCells(T, Counter)(size_t capacity) @trusted nothrow @nogc
{
    alias Item = Cell!(T, Counter);
    auto base = cast(Item*) malloc(capacity * Item.sizeof);
    return base is null ? null : base[0 .. capacity];
}

// SAFETY: The noncopyable ring exclusively owns this malloc allocation. Only
// destruction after the final borrow can release it.
private void releaseCells(T, Counter)(scope Cell!(T, Counter)[] cells) @trusted nothrow @nogc
{
    free(cells.ptr);
}

// SAFETY: The producer gate and acquire of the recycled sequence give this call
// exclusive access to the cell. The transfer constraint excludes managed data.
private void storePayload(T, Counter)(ref scope Cell!(T, Counter) cell, ref scope const T value) @trusted nothrow @nogc
{
    memcpy(cell.payload.ptr, &value, T.sizeof);
}

// SAFETY: The consumer owns a published cell until recycling its sequence. The
// cell was initialized from a T, and neither byte span escapes this call.
private T loadPayload(T, Counter)(ref scope Cell!(T, Counter) cell) @trusted nothrow @nogc
{
    T result = void;
    memcpy(&result, cell.payload.ptr, T.sizeof);
    return result;
}

version (unittest)
{
    @("sequence cells recycle across reduced counter wrap")
    unittest
    {
        SequenceRing!(uint, true, ubyte) ring;
        assert(ring.initialize(4, 254) == Status.ok);
        foreach (cycle; 0U .. 300U)
        {
            foreach (slot; 0U .. 4U)
                assert(ring.send(cycle * 4 + slot) == Status.ok);
            assert(ring.send(42) == Status.resourceExhausted);
            foreach (slot; 0U .. 4U)
            {
                const received = ring.receive();
                assert(received.ok() && received.value == cycle * 4 + slot);
            }
            assert(ring.receive().error.code == Status.unavailable);
        }
    }
}
