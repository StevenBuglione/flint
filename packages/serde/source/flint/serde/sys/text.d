/++
A GC copy of a short character slice that references no druntime array template. Private to `flint:serde`.

Under batch compile scope LDC emits every template instance of the package into its first archive object
(`flint.serde.ffi.yaml_events.o`). A `.idup` or `new char[]` in `java_number` therefore made every caller of
`javaDoubleString` link that object, and through its other instances the TOML and JSON modules and the arena's GC
root machinery. `copyText` calls druntime's C allocation entry point instead, so a leaf that only formats a number
links `java_number`, `shortest` and this module.
+/
module flint.serde.sys.text;

import core.memory : GC;

@safe:

// druntime's allocator behind `new` and `.idup`; it raises OutOfMemoryError rather than returning null.
private extern (C) void* gc_malloc(size_t size, uint attributes, const scope TypeInfo type) pure nothrow @system;

/// A new immutable GC copy of `text`; null when `text` is empty, as `.idup` gives an empty slice.
// The block holds no pointers, so NO_SCAN is exact.
// SAFETY: gc_malloc returns a fresh unshared block of text.length bytes; exactly that many are copied, then it
// escapes only as immutable chars, so it is never written again.
@trusted string copyText(scope const(char)[] text) pure nothrow
{
    if (text.length == 0)
        return null;
    auto block = (cast(char*) gc_malloc(text.length, GC.BlkAttr.NO_SCAN, null))[0 .. text.length];
    block[] = text[];
    return cast(string) block;
}

unittest
{
    char[8] source = "1.0E-5\0\0";
    const copy = copyText(source[0 .. 6]);
    assert(copy == "1.0E-5");
    assert(copy.ptr !is source.ptr);
    source[0] = '9';
    assert(copy == "1.0E-5", "the copy does not alias its source");
}

unittest
{
    assert(copyText(null) is null);
    char[4] source;
    assert(copyText(source[0 .. 0]).length == 0);
}

unittest
{
    // Every length up to 300 with pseudo-random bytes, against .idup, then a collection.
    char[300] source;
    uint state = 0x9E3779B9;
    foreach (length; 0 .. source.length + 1)
    {
        foreach (ref c; source[0 .. length])
        {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            c = cast(char) state;
        }
        const copy = copyText(source[0 .. length]);
        assert(copy == source[0 .. length].idup);
    }
    GC.collect();
}
