/++
Small structs stored inline in an `Any` instead of in a GC `Box` (no allocation per `Any.of`). Private to
`flint:engine-aot`; only `flint.engine.aot.any` uses it.

The storage is `Any`'s own 32 bytes of value fields, from its `Object` field on: an object reference, a word that
overlaps a pointer, a length and a pointer. A struct goes inline only when it fits at an offset where every word it
keeps a pointer in is one the GC treats as a pointer (words 0, 1 and 3), so a precise collector still sees each
pointer and a conservative one scans all of them anyway. Only plain structs qualify: at most 8-byte alignment, and
no postblit, copy constructor or destructor, so copying the words copies the value.
+/
module flint.engine.aot.sys.inline;

@safe:

/// The bytes of value storage an `Any` offers, and which of its words the GC treats as pointers.
enum size_t inlineBytes = 32;
private enum bool[4] pointerWords = [true, true, false, true];

/// The byte offset at which `T` sits inline in an `Any`, or `size_t.max` when it does not qualify.
template inlineOffset(T)
{
    static if (is(T == struct) && T.alignof <= (void*).alignof && !__traits(hasMember, T,
            "__xpostblit") && !__traits(hasCopyConstructor, T) && !__traits(hasMember, T,
            "__xdtor") && !__traits(isNested, T))
        enum size_t inlineOffset = placement!T();
    else
        enum size_t inlineOffset = size_t.max;
}

/// Whether `T` is stored inline in an `Any`.
enum bool isInlineable(T) = inlineOffset!T != size_t.max;

private size_t placement(T)()
{
    enum bitmap = __traits(getPointerBitmap, T); // [size in bytes, then one bit per pointer-sized word]
    enum words = (T.sizeof + (void*).sizeof - 1) / (void*).sizeof;
    foreach (start; 0 .. 4)
    {
        if (start + words > 4)
            break;
        bool fits = true;
        foreach (w; 0 .. words)
        {
            const bit = (bitmap[1 + w / (8 * size_t.sizeof)] >> (w % (8 * size_t.sizeof))) & 1;
            if (bit && !pointerWords[start + w])
                fits = false;
        }
        if (fits)
            return start * (void*).sizeof;
    }
    return size_t.max;
}

/// The value of type `T` held in the 32 bytes that start at `first`. `Any` statically asserts that its value fields
/// span 32 contiguous bytes at pointer alignment, and `inlineOffset!T + T.sizeof <= 32` with `T.alignof <= 8`.
// SAFETY: the view stays inside Any's 32 value bytes and lives no longer than the Any (`return ref`).
@trusted ref inout(T) inlineValue(T)(return ref inout(Object) first) pure nothrow @nogc
        if (isInlineable!T)
{
    return *cast(inout(T)*)(cast(inout(ubyte)*) cast(inout(void)*)&first + inlineOffset!T);
}

/// Store `value` in the 32 bytes that start at `first`, zeroing the rest so equal values compare equal word by word.
/// `T` is a plain struct (no postblit, copy constructor or destructor), so a byte copy is a copy.
// SAFETY: writes exactly Any's 32 value bytes (see `inlineValue`) and retains nothing.
@trusted void storeInline(T)(ref Object first, ref const T value) pure nothrow @nogc if (isInlineable!T)
{
    auto bytes = (cast(ubyte*) cast(void*)&first)[0 .. inlineBytes];
    bytes[] = 0;
    bytes[inlineOffset!T .. inlineOffset!T + T.sizeof] = (cast(const(ubyte)*) cast(const(void)*)&value)[0 .. T.sizeof];
}

unittest
{
    static struct Greeting
    {
        long id;
        string content;
    }

    static struct Large
    {
        long[5] values;
    }

    static struct Counted
    {
        int n;
        this(this)
        {
        }
    }

    static struct Pointers
    {
        string a;
        string b;
    }

    // Greeting's pointer (word 2 of the struct) lands on word 3 when placed at offset 8.
    static assert(inlineOffset!Greeting == 8 && isInlineable!Greeting);
    static assert(!isInlineable!Large && !isInlineable!Counted && !isInlineable!int);
    static assert(isInlineable!Pointers && inlineOffset!Pointers == 0); // pointers at words 1 and 3

    // Positive: a struct with a string round-trips through storage laid out as Any's value fields are.
    static struct Fields
    {
        Object first;
        long second;
        string third;
    }

    static assert(Fields.sizeof == inlineBytes);
    Fields fields;
    const greeting = Greeting(7, "hello");
    storeInline(fields.first, greeting);
    assert(inlineValue!Greeting(fields.first) == greeting);
    inlineValue!Greeting(fields.first).id = 8;
    assert(inlineValue!Greeting(fields.first).id == 8 && inlineValue!Greeting(fields.first).content == "hello");
    // Negative: storing a default value clears every byte, so no stale bits stay behind.
    const blank = Greeting.init;
    storeInline(fields.first, blank);
    assert(fields.first is null && fields.second == 0 && fields.third is null);
}
