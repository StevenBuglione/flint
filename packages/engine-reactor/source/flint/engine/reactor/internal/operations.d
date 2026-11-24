module flint.engine.reactor.internal.operations;

import flint.arena : Error, Result, Status;
import flint.engine.reactor.sys.chunks : Chunked;
import flint.engine.reactor.types : Completion, ConnectionId;

@safe:

/// Slot indices fit below maxPendingIoPerCore (8192); the remaining token bits carry the generation.
package(flint.engine.reactor) enum operationSlotBits = 13;
private enum slotMask = (1UL << operationSlotBits) - 1;
/// A slot retires only after 2^50 reservations, so one busy slot never exhausts the fixed table. Tokens stay below
/// the top bit, which marks a descriptor poll (internal/polls.d).
private enum maxGeneration = ulong.max >> (operationSlotBits + 1);

package(flint.engine.reactor) struct OperationId
{
    uint slot = uint.max;
    ulong generation;

    ulong token() const pure nothrow @nogc
    {
        return (generation << operationSlotBits) | slot;
    }

    static OperationId fromToken(ulong token) pure nothrow @nogc
    {
        return OperationId(cast(uint)(token & slotMask), token >> operationSlotBits);
    }
}

private enum Phase : ubyte
{
    free,
    queued,
    inFlight,
    ready
}

private struct Operation
{
    ConnectionId connection;
    ulong generation;
    uint next;
    Phase phase;
    Status cancellation;
}

/// Owner-thread only. The OS token remains valid through callback delivery. Slots are allocated in chunks as they
/// are first used, outside the GC heap (an operation holds no references): returned slots are reused first, most
/// recent first, so a worker's live operations stay in its lowest chunks.
package(flint.engine.reactor) struct OperationTable
{
    private Chunked!Operation slots;
    private uint nextFree = uint.max;
    /// Slots below this index were handed out at least once; the rest have never been used.
    private uint used;

    @disable this(this);

    Status initialize(uint capacity) nothrow @nogc
    {
        assert(capacity <= 1U << operationSlotBits);
        return slots.reserve(capacity);
    }

    void release() nothrow @nogc
    {
        slots.release();
        nextFree = uint.max;
        used = 0;
    }

    /// The slot the next `reserve` hands out, or `uint.max` when the table is full.
    uint nextSlot() const nothrow @nogc
    {
        if (nextFree != uint.max)
            return nextFree;
        return used < slots.length ? used : uint.max;
    }

    Result!OperationId reserve(ConnectionId connection) nothrow @nogc
    {
        if (connection.generation == 0)
            return Result!OperationId(OperationId.init, Error(Status.invalidArgument, "invalid connection"));
        const index = nextSlot;
        if (index == uint.max)
            return Result!OperationId(OperationId.init, Error(Status.resourceExhausted, "operation table full"));
        if (index == used)
        {
            if (slots.ensure(index) != Status.ok)
                return Result!OperationId(OperationId.init, Error(Status.outOfMemory, "operation table chunk"));
            ++used;
        }
        else
            nextFree = slots[index].next;
        auto slot = &slots[index];
        ++slot.generation;
        // Public IoId tickets carry the low 32 bits, and a zero ticket generation means no operation.
        if (cast(uint) slot.generation == 0)
            ++slot.generation;
        slot.connection = connection;
        slot.phase = Phase.queued;
        slot.cancellation = Status.ok;
        return Result!OperationId(OperationId(index, slot.generation));
    }

    Status start(OperationId id) nothrow @nogc
    {
        if (!contains(id))
            return Status.notFound;
        auto slot = &slots[id.slot];
        if (slot.phase != Phase.queued)
            return Status.conflict;
        if (slot.cancellation != Status.ok)
            return slot.cancellation;
        slot.phase = Phase.inFlight;
        return Status.ok;
    }

    Status requestCancellation(OperationId id, Status reason) nothrow @nogc
    {
        if (reason != Status.cancelled && reason != Status.timedOut)
            return Status.invalidArgument;
        if (!contains(id))
            return Status.notFound;
        auto slot = &slots[id.slot];
        if (slot.phase == Phase.ready)
            return Status.conflict;
        if (slot.cancellation == Status.ok)
            slot.cancellation = reason;
        return Status.ok;
    }

    /// A requested cancellation replaces the final status, except for a read the kernel completed with
    /// data first: those bytes are already consumed from the socket, so they are delivered as success.
    Result!Completion finish(OperationId id, Status status, size_t bytes, bool read = false) nothrow @nogc
    {
        if (!contains(id))
            return Result!Completion(Completion.init, Error(Status.notFound, "invalid operation"));
        auto slot = &slots[id.slot];
        if (slot.phase != Phase.inFlight && !(slot.phase == Phase.queued && slot.cancellation != Status.ok))
            return Result!Completion(Completion.init, Error(Status.conflict, "unexpected final completion"));
        slot.phase = Phase.ready;
        if (slot.cancellation != Status.ok && !(read && status == Status.ok && bytes != 0))
            status = slot.cancellation;
        return Result!Completion(Completion(slot.connection, status, bytes));
    }

    Status retire(OperationId id) nothrow @nogc
    {
        if (!contains(id))
            return Status.notFound;
        auto slot = &slots[id.slot];
        if (slot.phase != Phase.ready)
            return Status.conflict;
        slot.phase = Phase.free;
        if (slot.generation < maxGeneration - 1)
        {
            slot.next = nextFree;
            nextFree = id.slot;
        }
        return Status.ok;
    }

    private bool contains(OperationId id) const nothrow @nogc
    {
        return id.slot < used && slots[id.slot].phase != Phase.free && slots[id.slot].generation == id.generation;
    }
}

@("operation slots stay reusable after 2^32 reservations and never repeat a kernel token")
unittest
{
    // A worker owns only maxPendingIoPerCore slots and its free list reuses the most recent slot first,
    // so one hot slot passes 2^32 reservations after hours of sustained traffic.
    OperationTable table;
    assert(table.initialize(1) == Status.ok);
    scope (exit)
        table.release();
    assert(table.slots.ensure(0) == Status.ok);
    table.slots[0].generation = uint.max - 2;
    const connection = ConnectionId(0, 0, 1);
    OperationId previous;
    foreach (round; 0 .. 4)
    {
        const reserved = table.reserve(connection);
        assert(reserved.ok, "a busy operation slot retired permanently");
        const id = reserved.value;
        assert(id.token != previous.token && OperationId.fromToken(id.token) == id);
        assert(cast(uint) id.generation != 0, "the public ticket generation must stay nonzero");
        assert(table.start(previous) == Status.notFound);
        assert(table.start(id) == Status.ok);
        assert(table.finish(id, Status.ok, 0).ok);
        assert(table.retire(id) == Status.ok);
        previous = id;
    }
}

@("operation slots are allocated a chunk at a time and returned slots are reused before new ones")
unittest
{
    OperationTable table;
    assert(table.initialize(1 << operationSlotBits) == Status.ok);
    scope (exit)
        table.release();
    const connection = ConnectionId(0, 0, 1);
    OperationId[70] ids;
    foreach (ref id; ids)
        id = table.reserve(connection).value;
    assert(ids[0].slot == 0 && ids[69].slot == 69);
    assert(table.slots.present(127) && !table.slots.present(128), "only the chunks in use are allocated");
    foreach (id; ids[0 .. 3])
    {
        assert(table.start(id) == Status.ok && table.finish(id, Status.ok, 0).ok);
        assert(table.retire(id) == Status.ok);
    }
    assert(table.nextSlot == 2, "the most recently returned slot is reused first");
    assert(table.reserve(connection).value.slot == 2 && table.reserve(connection).value.slot == 1);
    assert(table.reserve(connection).value.slot == 0 && table.reserve(connection).value.slot == 70);
}
