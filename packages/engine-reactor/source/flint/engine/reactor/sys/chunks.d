module flint.engine.reactor.sys.chunks;

import flint.arena : Status;

@safe:

/++
A worker's per-slot table, allocated a chunk at a time as slots are first used, outside the GC heap.

The reactor reserves tables for its limits (4,096 connections and 4,160 operations per worker under the HTTP engine),
and allocating them whole put them on the GC heap: the live set every collection marks, and from which the heap's
size follows. Slots are handed out lowest first, so a server holding 64 connections uses one chunk of each table. A
chunk of a type with pointers is a GC root while it exists; a pointer-free one is not scanned at all. A new chunk's
elements are `T.init`.
+/
package(flint.engine.reactor) struct Chunked(T)
{
    import std.traits : hasIndirections;

    private T*[] chunks;
    private size_t capacity;
    private size_t chunkLength;

    @disable this(this);

    /// Room for `capacity` elements in chunks of `chunkLength`; no chunk is allocated yet.
    // SAFETY: The chunk-pointer array is calloc'd for exactly the chunk count and owned by this table until release.
    @trusted Status reserve(size_t capacity, size_t chunkLength = 64) nothrow @nogc
    {
        import core.stdc.stdlib : calloc;

        if (chunks.ptr !is null || chunkLength == 0)
            return Status.invalidArgument;
        const count = (capacity + chunkLength - 1) / chunkLength;
        auto pointers = count ? cast(T**) calloc(count, (T*).sizeof) : null;
        if (count && pointers is null)
            return Status.outOfMemory;
        chunks = pointers[0 .. count];
        this.capacity = capacity;
        this.chunkLength = chunkLength;
        return Status.ok;
    }

    /// The elements the table may hold.
    size_t length() const pure nothrow @nogc
    {
        return capacity;
    }

    /// Whether the chunk holding `index` exists.
    bool present(size_t index) const pure nothrow @nogc
    {
        return index < capacity && chunks[index / chunkLength] != null;
    }

    /// Allocate the chunk holding `index`, if it does not exist yet.
    // SAFETY: Each chunk is malloc'd for chunkLength elements, initialized to T.init before any use, and registered
    // as a GC root (when T holds pointers) before a reference is stored in it; release undoes both.
    @trusted Status ensure(size_t index) nothrow @nogc
    {
        import core.memory : GC;
        import core.stdc.stdlib : malloc;

        if (index >= capacity)
            return Status.invalidArgument;
        const chunk = index / chunkLength;
        if (chunks[chunk] != null)
            return Status.ok;
        auto block = cast(T*) malloc(chunkLength * T.sizeof);
        if (block is null)
            return Status.outOfMemory;
        static immutable T initial;
        foreach (ref element; block[0 .. chunkLength])
            (cast(ubyte*)&element)[0 .. T.sizeof] = (cast(const(ubyte)*)&initial)[0 .. T.sizeof];
        static if (hasIndirections!T)
            GC.addRange(block, chunkLength * T.sizeof);
        chunks[chunk] = block;
        return Status.ok;
    }

    /// The element at `index`; its chunk must exist.
    // SAFETY: The index is checked against the capacity and its chunk's presence; the chunk lives until release.
    @trusted ref inout(T) opIndex(size_t index) inout return nothrow @nogc
    {
        assert(present(index), "chunk not allocated");
        return chunks[index / chunkLength][index % chunkLength];
    }

    /// The elements `begin .. end`, which lie within one chunk; null when that chunk does not exist.
    // SAFETY: Both bounds are checked to lie in one existing chunk, which lives until release.
    @trusted T[] slice(size_t begin, size_t end) return nothrow @nogc
    {
        assert(begin <= end && end <= capacity && (end == begin || begin / chunkLength == (end - 1) / chunkLength));
        if (begin == end || !present(begin))
            return null;
        const offset = begin % chunkLength;
        return chunks[begin / chunkLength][offset .. offset + (end - begin)];
    }

    /// Free every chunk, after the worker stopped using the table.
    // SAFETY: Called once by the owner after its last use: roots are removed before the memory is freed.
    @trusted void release() nothrow @nogc
    {
        import core.memory : GC;
        import core.stdc.stdlib : free;

        foreach (ref chunk; chunks)
        {
            if (chunk is null)
                continue;
            static if (hasIndirections!T)
                GC.removeRange(chunk);
            free(chunk);
            chunk = null;
        }
        free(chunks.ptr);
        chunks = null;
        capacity = 0;
    }
}

@("a chunked table allocates the chunk a slot needs, initialized, and keeps GC references alive")
@system unittest
{
    import core.memory : GC;

    static struct Slot
    {
        int marker = 7;
        int* payload;
    }

    Chunked!Slot table;
    assert(table.reserve(1_000) == Status.ok);
    scope (exit)
        table.release();
    assert(table.length == 1_000 && !table.present(0) && !table.present(999));
    assert(table.ensure(130) == Status.ok);
    assert(table.present(128) && table.present(191) && !table.present(127) && !table.present(192));
    assert(table[130].marker == 7 && table[130].payload is null, "a new chunk holds T.init");
    table[130].payload = new int(42);
    GC.collect();
    foreach (_; 0 .. 1_000)
        cast(void) new int[](4);
    assert(*table[130].payload == 42, "a chunk with pointers is a GC root");
    assert(table.ensure(1_000) == Status.invalidArgument);
    assert(table.slice(128, 132).length == 4 && table.slice(0, 4) is null);
}
