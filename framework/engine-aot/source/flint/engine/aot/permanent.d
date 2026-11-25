/++
Start-up tables in one GC block (Flint AOT contract 3, generated code).

A collection's pause is mostly the first touch of each reachable object, about 50 ns apiece
(docs/spring/phase1/gc.md section 3b), and the live heap after start-up is almost all permanent start-up data. A
generated module used to build its tables as hundreds of objects: a GC array per string list, per annotation list and
per descriptor list, a `Box` per annotation value and an object per descriptor. `Permanent` carves all of them from
shared small blocks (`flint.engine.aot.sys.region`: 2 KB chunks, so the data stays in druntime's small pages and the
collection threshold it sets is unchanged), so a few dozen pieces are one object. The generator reserves the module's
total up front (`bytes`, `boxBytes`, `objectBytes`), which sizes the last chunk; any request still succeeds.

Values are exactly what the literals built: a list is a fresh mutable array whose appends copy, a boxed value is a
real `Box!T` that `Any.get!T` returns by `ref`, and an object is constructed by its own constructor. Only types with
nothing to destroy qualify, since the block is never finalized.
+/
module flint.engine.aot.permanent;

import flint.engine.aot.any : Any, Box;
import flint.engine.aot.sys.region : isCarvable, isPlaceable, Region, regionAligned, regionAlignment;

@safe:

/// A generated module's start-up tables, carved from one GC block.
struct Permanent
{
    private Region region;

    /// Plan for `bytes`, the generator's total of `bytes`, `boxBytes` and `objectBytes` terms.
    this(size_t bytes) nothrow
    {
        region.reserve(bytes);
    }

    /// The array `[items]` (null when empty), in the block.
    T[] list(T)(scope T[] items...) nothrow if (isCarvable!T)
    {
        if (items.length == 0)
            return null;
        auto result = region.array!T(items.length);
        result[] = items[];
        return result;
    }

    /// `Any.of(value)`, with the box, when `T` needs one, in the block.
    Any any(T)(T value)
    {
        static if (Any.boxes!T && isPlaceable!(Box!(typeof(cast() value))))
            return Any.ofBox(make!(Box!(typeof(cast() value)))(value));
        else
            return Any.of(value);
    }

    /// `new C(args)`, in the block.
    C make(C, Args...)(auto ref Args args) if (isPlaceable!C)
    {
        C instance = region.blank!C();
        static if (__traits(hasMember, C, "__ctor"))
            instance.__ctor(args);
        else
            static assert(Args.length == 0, C.stringof ~ " has no constructor taking arguments");
        return instance;
    }

    /// Reserved bytes not yet carved.
    size_t remaining() const pure nothrow @nogc
    {
        return region.remaining;
    }

    /// The GC blocks holding everything carved so far: what a collection marks for these tables.
    size_t blocks() const pure nothrow @nogc
    {
        return region.blocks;
    }

    /// The reservation for `lists` lists of `T` holding `elements` values in all.
    static size_t bytes(T)(size_t lists, size_t elements) pure nothrow @nogc
    {
        return T.sizeof * elements + (T.sizeof % regionAlignment ? lists * (regionAlignment - 1) : 0);
    }

    /// The reservation for `count` values of `T` passed to `any`: their boxes, or 0 when `T` sits inline.
    static size_t boxBytes(T)(size_t count) pure nothrow @nogc
    {
        static if (Any.boxes!T && isPlaceable!(Box!T))
            return count * regionAligned(__traits(classInstanceSize, Box!T));
        else
            return 0;
    }

    /// The reservation for `count` objects of class `C`.
    static size_t objectBytes(C)(size_t count) pure nothrow @nogc
    {
        return count * regionAligned(__traits(classInstanceSize, C));
    }
}

unittest
{
    import core.memory : GC;

    static struct Mapping
    {
        string name;
        string[] path;
        int order = 3;
        long[4] spare;
    }

    static struct Small
    {
        int value;
    }

    static final class Table
    {
        string name;
        string[] rows;

        this(string name) pure nothrow
        {
            this.name = name;
        }
    }

    enum size_t reserved = Permanent.bytes!string(3,
                4) + Permanent.boxBytes!Mapping(1) + Permanent.boxBytes!Small(1) + Permanent.objectBytes!Table(1);
    static assert(Permanent.boxBytes!Small(5) == 0 && Permanent.boxBytes!string(5) == 0);
    auto permanent = Permanent(reserved);
    const paths = permanent.list!string("/owners", "/owners/{id}");
    auto table = permanent.make!Table("owners");
    table.rows = permanent.list!string("a");
    auto mapping = permanent.any(() {
        Mapping m;
        m.name = "get";
        m.path = permanent.list!string("/x");
        return m;
    }());
    const small = permanent.any(Small(4));
    assert(permanent.blocks == 1);

    assert(paths == ["/owners", "/owners/{id}"] && table.name == "owners" && table.rows == ["a"]);
    assert(mapping.get!Mapping.name == "get" && mapping.get!Mapping.path == ["/x"] && mapping.get!Mapping.order == 3);
    assert(mapping.typeName == Any.of(Mapping.init).typeName && mapping.holds!Mapping);
    mapping.get!Mapping.order = 9; // returned by ref into the box, as for Any.of
    assert(mapping.get!Mapping.order == 9 && mapping.box!Mapping !is null);
    assert(small.get!Small.value == 4);
    assert(permanent.list!string() is null);
    assert(GC.addrOf(cast(void*) table) !is null);

    // An undersized plan still holds every value.
    auto tight = Permanent(16);
    const first = tight.list!string("one");
    const second = tight.list!string("two", "three");
    assert(first == ["one"] && second == ["two", "three"] && tight.blocks == 2);
}
