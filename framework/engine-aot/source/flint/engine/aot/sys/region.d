/++
A bump region over zeroed GC blocks, for start-up data that lives as long as the process (`flint.engine.aot.permanent`).
Private to `flint:engine-aot`; applications never import it.

A collection marks each reachable GC object once, and the first touch of each one costs about 50 ns of the pause
(docs/spring/phase1/gc.md section 3b). Generated AOT tables held hundreds of small arrays, boxes and descriptors,
each its own object. Carved from shared blocks, a few dozen pieces are one object: the GC keeps a block alive through
any interior pointer and scans it whole.

Blocks are chunks of `chunkBytes`, druntime's largest small size class, so carved data stays in small-object pages.
That matters: druntime collects when the small pages in use reach the live small pages times `heapSizeFactor`, so
permanent data moved to large pages would make request garbage trigger collections sooner (measured: petclinic's
owner run collected 6 times instead of 4). A piece larger than a chunk gets a block of its own, as a literal would.

Every block is scanned (no `NO_SCAN`), not appendable (an append to a carved slice copies it, as it does for a slice
of static data) and has no finalizer, so only types without destructors are carved. Blocks are zeroed to their whole
capacity, so an unused tail holds no stale pointers.
+/
module flint.engine.aot.sys.region;

@safe:

/// The alignment of every carved piece.
enum size_t regionAlignment = 8;

/// `bytes` rounded up to `regionAlignment`.
size_t regionAligned(size_t bytes) pure nothrow @nogc
{
    return (bytes + regionAlignment - 1) & ~(regionAlignment - 1);
}

/// Whether `T` may be carved: a plain value at most 8-byte aligned, copied by its bits, with nothing to destroy.
template isCarvable(T)
{
    static if (is(T == struct) || is(T == union))
        enum bool isCarvable = T.alignof <= regionAlignment && !__traits(hasMember, T, "__xdtor")
            && !__traits(hasMember, T, "__xpostblit") && !__traits(hasCopyConstructor, T)
            && !__traits(hasMember, T, "opAssign") && !__traits(isNested, T);
    else static if (is(T == E[n], E, size_t n))
        enum bool isCarvable = isCarvable!E;
    else
        enum bool isCarvable = T.alignof <= regionAlignment;
}

/// Whether class `C` may be placed: a complete D class, at most 8-byte aligned, with no destructor anywhere in its
/// hierarchy (a carved object is never finalized) and no outer context.
enum bool isPlaceable(C) = is(C == class) && !__traits(isAbstractClass, C) && !__traits(isNested,
            C) && !__traits(hasMember, C, "__xdtor") && __traits(getLinkage, C) == "D"
    && __traits(classInstanceAlignment, C) <= regionAlignment;

/// The size of a chunk: druntime's largest small size class (larger requests take whole pages).
enum size_t chunkBytes = 2048;

/// The bump region. Pieces never overlap; a piece the current chunk cannot hold starts a new chunk.
struct Region
{
    private void[] rest; // the current chunk's unused tail
    private size_t planned; // reserved bytes no block holds yet
    private size_t count; // blocks allocated

    /// Plan for `bytes` in all: the last chunk is sized to what is left of the plan instead of a whole chunk.
    void reserve(size_t bytes) nothrow
    {
        planned = regionAligned(bytes);
    }

    /// Reserved bytes not yet carved: the current chunk's tail and the plan no block holds yet.
    size_t remaining() const pure nothrow @nogc
    {
        return rest.length + planned;
    }

    /// The blocks allocated so far: the objects a collection marks for everything carved.
    size_t blocks() const pure nothrow @nogc
    {
        return count;
    }

    /// `length` values of `T`, each `T.init`, in the region.
    T[] array(T)(size_t length) nothrow if (isCarvable!T)
    {
        if (length == 0)
            return null;
        auto result = typed!T(take(regionAligned(T.sizeof * length)), length);
        static if (!__traits(isZeroInit, T))
            result[] = T.init;
        return result;
    }

    /// An instance of `C` holding its initial field values, constructor not run (the caller runs it).
    C blank(C)() nothrow if (isPlaceable!C)
    {
        return placed!C(take(regionAligned(__traits(classInstanceSize, C))));
    }

    private void[] take(size_t bytes) nothrow
    {
        if (bytes > chunkBytes)
        {
            count++;
            planned -= bytes < planned ? bytes : planned;
            return block(bytes)[0 .. bytes];
        }
        if (bytes > rest.length)
        {
            const wanted = planned > chunkBytes ? chunkBytes : planned;
            rest = block(wanted > bytes ? wanted : bytes);
            count++;
            planned -= rest.length < planned ? rest.length : planned;
        }
        auto piece = rest[0 .. bytes];
        rest = rest[bytes .. $];
        return piece;
    }
}

// GC.calloc returns a fresh block of at least `bytes` (attributes 0: scanned, not appendable, no finalizer), zeroed
// for `bytes`; GC.sizeOf is its whole capacity, whose tail is zeroed here. The slice spans that block and nothing else
// references it yet.
// SAFETY: the bounds, initialization and lifetime argument just above.
private @trusted void[] block(size_t bytes) nothrow
{
    import core.memory : GC;
    import core.stdc.string : memset;

    auto memory = GC.calloc(bytes);
    if (memory is null)
        assert(0, "out of memory");
    const capacity = GC.sizeOf(memory);
    assert(capacity >= bytes);
    memset(memory + bytes, 0, capacity - bytes);
    return memory[0 .. capacity];
}

// `piece` is a fresh, zeroed, 8-byte aligned region piece of at least `T.sizeof * length` bytes (Region.array
// asks for that much); `isCarvable!T` limits T to plain types at most 8-byte aligned, which zeroed or T.init bits
// make valid. The GC scans the block, so pointers stored in the values keep their targets alive.
// SAFETY: the bounds, initialization and lifetime argument just above.
private @trusted T[] typed(T)(void[] piece, size_t length) nothrow
{
    assert(piece.length >= T.sizeof * length);
    return (cast(T*) piece.ptr)[0 .. length];
}

// `piece` is a fresh, zeroed, 8-byte aligned region piece of at least `classInstanceSize!C` bytes (Region.blank
// asks for that much); copying C's initializer sets the vtable, the null monitor and every field's initial value,
// which is the state `new C` reaches before its constructor. `isPlaceable!C` excludes abstract, nested, non-D and
// destructible classes and alignment above 8. The block is scanned and kept alive by the returned reference.
// SAFETY: the bounds, initialization and lifetime argument just above.
private @trusted C placed(C)(void[] piece) nothrow
{
    enum size = __traits(classInstanceSize, C);
    auto initial = __traits(initSymbol, C);
    assert(piece.length >= size && initial.length == size);
    (cast(ubyte[]) piece)[0 .. size] = cast(const(ubyte)[]) initial[];
    return cast(C) piece.ptr;
}

unittest
{
    import core.memory : GC;

    static struct Plain
    {
        string name;
        int count = 7;
        string[] items;
    }

    static final class Node
    {
        string label = "initial";
        Node next;
        int value;
    }

    Region region;
    region.reserve(200);
    assert(region.remaining == 200 && region.blocks == 0);
    auto names = region.array!string(3);
    assert(names.length == 3 && names[0] is null);
    names[] = ["a", "b", "c"];
    auto plains = region.array!Plain(2);
    assert(plains[1].count == 7 && plains[0].name is null);
    auto node = region.blank!Node();
    assert(node.label == "initial" && node.next is null && typeid(node) is typeid(Node));
    node.next = new Node; // a GC pointer stored in the region keeps its target alive
    // One small block, sized to the plan, holds all three pieces.
    assert(region.blocks == 1 && region.remaining < 200);
    assert(GC.addrOf(cast(void*)&names[0]) is GC.addrOf(cast(void*) node));
    assert(region.rest.length < chunkBytes); // the block is a small one: the plan, rounded to its size class
    assert(region.array!int(0) is null);

    // A slice of the region never appends in place.
    auto copy = names;
    copy ~= "d";
    assert(names == ["a", "b", "c"] && copy == ["a", "b", "c", "d"]);
    assert(plains[0].name is null && plains[0].count == 7);

    // The block's tail, beyond what calloc was asked to zero, is zeroed too.
    auto tail = region.array!ulong(region.rest.length / ulong.sizeof);
    foreach (word; tail)
        assert(word == 0);
    assert(region.blocks == 1);

    // Past the plan, a piece starts a new chunk; nothing overlaps.
    auto more = region.array!long(64);
    assert(region.blocks == 2 && more.length == 64 && more[63] == 0);
    more[] = -1;
    assert(names == ["a", "b", "c"] && node.label == "initial");

    // A piece larger than a chunk gets a block of its own, and the chunk's tail stays in use.
    const before = region.rest.length;
    auto large = region.array!long(300);
    assert(region.blocks == 3 && large.length == 300 && region.rest.length == before);
    assert(GC.addrOf(cast(void*)&large[0]) !is GC.addrOf(cast(void*)&more[0]));

    // An unplanned region still serves every request.
    Region empty;
    const one = empty.array!string(1);
    assert(one.length == 1 && empty.blocks == 1);
}

unittest
{
    static class Destructible
    {
        ~this()
        {
        }
    }

    static struct Owned
    {
        ~this()
        {
        }
    }

    static struct Copied
    {
        this(this)
        {
        }
    }

    static abstract class Shape
    {
        abstract int sides();
    }

    static class Derived : Destructible
    {
    }

    static assert(!isPlaceable!Destructible && !isPlaceable!Derived && !isPlaceable!Shape);
    static assert(!isCarvable!Owned && !isCarvable!Copied);
    static assert(!__traits(compiles, (ref Region r) => r.blank!Destructible()));
    static assert(!__traits(compiles, (ref Region r) => r.array!Owned(1)));
    static assert(isCarvable!string && isCarvable!(int[]) && isPlaceable!Object);
}
