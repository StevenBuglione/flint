/// Bounded caller-owned storage with generation-checked byte handles.
module flint.arena;

import flint.arena.sys.borrow : haltActiveBorrow;
import flint.arena.sys.owner : nextOwner;

@safe:

/// Operational result codes common to the framework.
enum Status : int
{
    ok,
    invalidArgument,
    outOfMemory,
    cancelled,
    timedOut,
    notFound,
    conflict,
    ioError,
    unavailable,
    unsupported,
    permissionDenied,
    resourceExhausted
}

/// Allocation-free error information.
struct Error
{
    /// Result category.
    Status code;
    /// Static diagnostic message.
    string message;
    /// Input byte offset, or size_t.max when inapplicable.
    size_t offset = size_t.max;
}

/// A value together with its operation status.
struct Result(T)
{
    /// Meaningful after success.
    T value;
    /// Outcome and optional diagnostic.
    Error error;

    /// True when the operation succeeded.
    bool ok() const pure nothrow @nogc
    {
        return error.code == Status.ok;
    }
}

/// An opaque arena handle with no pointer to backing storage.
struct Buffer
{
    private ulong owner;
    private ulong epoch;
    private size_t start;
    private size_t count;

    private this(ulong owner, ulong epoch, size_t start, size_t count) nothrow @nogc
    {
        this.owner = owner;
        this.epoch = epoch;
        this.start = start;
        this.count = count;
    }

    /// Number of bytes in the handle, regardless of its current validity.
    size_t length() const pure nothrow @nogc
    {
        return count;
    }
}

/// A handle naming UTF-8 bytes whose encoding is checked by the consumer.
struct Text
{
    /// The byte handle to resolve against the owning arena.
    Buffer bytes;
}

/// Cumulative statistics for a single arena.
struct ArenaStats
{
    /// Total backing bytes.
    size_t capacity;
    /// Current bytes consumed, including alignment padding.
    size_t used;
    /// Greatest number of bytes consumed in any epoch.
    size_t peak;
    /// Number of successful resets.
    ulong resets;
}

private alias ReadVisitor = void delegate(scope const(ubyte)[]) @safe nothrow @nogc;
private alias WriteVisitor = void delegate(scope ubyte[]) @safe nothrow @nogc;

/// Thread-confined arena borrowing caller-owned storage for its entire lifetime.
struct RequestArena
{
    private ubyte[] storage;
    private size_t cursor;
    private size_t peak;
    private uint activeBorrows;
    private ulong owner;
    private ulong epoch;

    @disable this(this);
    // Replacing a live arena from its visitor would discard the active-borrow count.
    @disable void opAssign(RequestArena replacement);

    /// Borrow backing storage, which must be reserved exclusively for this arena.
    this(return scope ubyte[] backing) nothrow @nogc
    {
        storage = backing;
        owner = nextOwner();
    }

    ~this() scope nothrow @nogc
    {
        owner = 0;
        if (activeBorrows != 0)
            haltActiveBorrow();
    }

    /// D runtime moves may only transfer a quiescent arena.
    void opPostMove(scope const ref RequestArena original) scope nothrow @nogc
    {
        if (original.activeBorrows != 0)
        {
            // Druntime already copied the value. Retire the copy before trapping.
            owner = 0;
            activeBorrows = 0;
            haltActiveBorrow();
        }
    }

    /// Allocate zeroed bytes. Nonempty allocations have the requested alignment.
    Result!Buffer allocate(size_t bytes, size_t alignment = 8) scope nothrow @nogc
    {
        auto allocation = reserve(bytes, alignment);
        if (allocation.ok() && bytes != 0)
        {
            immutable start = allocation.value.start;
            storage[start .. cursor] = 0;
        }
        return allocation;
    }

    /// Copy the supplied bytes into a newly initialized buffer.
    Result!Buffer copyIn(scope const(ubyte)[] source) scope nothrow @nogc
    {
        auto allocation = reserve(source.length, 8);
        if (!allocation.ok() || source.length == 0)
            return allocation;

        copyBytes(storage[allocation.value.start .. cursor], source);
        return allocation;
    }

    /// Extend the most recent allocation with initialized bytes. A failed append preserves both handles and storage.
    Status append(ref Buffer handle, scope const(ubyte)[] tail) scope nothrow @nogc
    {
        if (!valid(handle))
            return Status.invalidArgument;
        if (activeBorrows != 0 || handle.count != cursor - handle.start)
            return Status.conflict;
        if (tail.length > storage.length - cursor)
            return Status.outOfMemory;

        immutable end = cursor + tail.length;
        copyBytes(storage[cursor .. end], tail);
        cursor = end;
        handle.count += tail.length;
        if (cursor > peak)
            peak = cursor;
        return Status.ok;
    }

    private static void copyBytes(scope ubyte[] destination, scope const(ubyte)[] source) nothrow @nogc
    {
        // Copy backwards when the source begins below the destination to allow overlap.
        if (cast(size_t) source.ptr < cast(size_t) destination.ptr)
        {
            for (size_t index = source.length; index > 0; --index)
                destination[index - 1] = source[index - 1];
        }
        else
        {
            foreach (index, byteValue; source)
                destination[index] = byteValue;
        }
    }

    /// Present a checked handle as a read-only slice for the visitor's duration.
    Status read(Buffer handle, scope ReadVisitor visitor) scope nothrow @nogc
    {
        if (visitor is null || !valid(handle))
            return Status.invalidArgument;
        if (activeBorrows == uint.max)
            return Status.resourceExhausted;

        ++activeBorrows;
        scope (exit)
            --activeBorrows;
        visitor(storage[handle.start .. handle.start + handle.count]);
        return Status.ok;
    }

    /// Present a checked handle as a writable slice for the visitor's duration.
    Status write(Buffer handle, scope WriteVisitor visitor) scope nothrow @nogc
    {
        if (visitor is null || !valid(handle))
            return Status.invalidArgument;
        if (activeBorrows == uint.max)
            return Status.resourceExhausted;

        ++activeBorrows;
        scope (exit)
            --activeBorrows;
        visitor(storage[handle.start .. handle.start + handle.count]);
        return Status.ok;
    }

    /// Reclaim all space and invalidate every existing handle in constant time.
    Status reset() scope nothrow @nogc
    {
        if (activeBorrows != 0)
            return Status.conflict;
        if (owner == 0)
            return Status.resourceExhausted;
        if (epoch == ulong.max)
        {
            owner = 0;
            return Status.resourceExhausted;
        }
        ++epoch;
        cursor = 0;
        return Status.ok;
    }

    /// Read usage statistics without borrowing the underlying bytes.
    ArenaStats stats() const scope nothrow @nogc
    {
        return ArenaStats(storage.length, cursor, peak, epoch);
    }

    private Result!Buffer reserve(size_t bytes, size_t alignment) scope nothrow @nogc
    {
        if (owner == 0)
            return Result!Buffer(Buffer.init, Error(Status.resourceExhausted, "arena identity exhausted"));
        if (alignment == 0 || alignment > 4096 || (alignment & (alignment - 1)) != 0)
            return Result!Buffer(Buffer.init, Error(Status.invalidArgument, "invalid arena alignment"));
        if (bytes == 0)
            return Result!Buffer(Buffer(owner, epoch, cursor, 0));

        immutable mask = alignment - 1;
        immutable startLowBits = (cast(size_t) storage.ptr & mask) + (cursor & mask);
        immutable padding = (0 - startLowBits) & mask;
        immutable remaining = storage.length - cursor;
        if (padding > remaining || bytes > remaining - padding)
            return Result!Buffer(Buffer.init, Error(Status.outOfMemory, "arena capacity exhausted"));

        immutable start = cursor + padding;
        cursor = start + bytes;
        if (cursor > peak)
            peak = cursor;
        return Result!Buffer(Buffer(owner, epoch, start, bytes));
    }

    private bool valid(Buffer handle) const scope nothrow @nogc
    {
        return owner != 0 && handle.owner == owner && handle.epoch == epoch && handle.start <= cursor
            && handle.count <= cursor - handle.start;
    }
}

/// Limits used when provisioning a native buffer pool.
struct BufferPoolOptions
{
    /// Backing bytes for each block.
    size_t blockBytes = 65_536;
    /// Maximum concurrently leased blocks.
    size_t blockCount = 256;
}

@("epoch exhaustion retires the arena and invalidates its outstanding handles")
unittest
{
    ubyte[8] backing;
    scope arena = RequestArena(backing[]);
    arena.epoch = ulong.max - 1;
    auto previous = arena.allocate(1);
    assert(previous.ok());
    assert(arena.reset() == Status.ok);
    assert(arena.read(previous.value, (scope const(ubyte)[]) @safe nothrow @nogc {
            assert(0, "the previous epoch unexpectedly accepted a handle");
        }) == Status.invalidArgument);

    auto finalHandle = arena.allocate(1);
    assert(finalHandle.ok());
    assert(arena.reset() == Status.resourceExhausted);
    assert(arena.allocate(0).error.code == Status.resourceExhausted);
    assert(arena.reset() == Status.resourceExhausted);
    assert(arena.read(finalHandle.value, (scope const(ubyte)[]) @safe nothrow @nogc {
            assert(0, "retired arena unexpectedly accepted a handle");
        }) == Status.invalidArgument);
}

@("borrow count cannot roll over")
unittest
{
    ubyte[8] backing;
    scope arena = RequestArena(backing[]);
    auto allocation = arena.allocate(1);
    assert(allocation.ok());
    scope (exit)
        arena.activeBorrows = 0;
    arena.activeBorrows = uint.max;
    assert(arena.write(allocation.value, (scope ubyte[]) @safe nothrow @nogc {
            assert(0, "saturated borrow count unexpectedly accepted a new borrow");
        }) == Status.resourceExhausted);
    assert(arena.activeBorrows == uint.max);
    assert(arena.reset() == Status.conflict);
}
