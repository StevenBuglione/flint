/++
Byte copies for the response-head writer: one `memmove` after an explicit length check.

A `@safe` slice assignment with bounds checks on lowers to druntime's `_d_array_slice_copy`, which checks lengths and
overlap generically: about 100 instructions for each of the dozens of small pieces a response head is built from
(R-67).
+/
module flint.engine.web.sys.copy;

@safe:

/// Copy `bytes` to the start of `target`. When they do not fit, copy nothing and return false.
// SAFETY: both slices are live for the call; bytes.length <= target.length is checked first, so memmove writes exactly
// bytes.length bytes inside target, and memmove allows the two ranges to overlap.
@trusted package(flint.engine.web) bool copyBytes(scope ubyte[] target, scope const(ubyte)[] bytes) pure nothrow @nogc
{
    import core.stdc.string : memmove;

    if (bytes.length > target.length)
        return false;
    if (bytes.length != 0)
        memmove(target.ptr, bytes.ptr, bytes.length);
    return true;
}

@("copyBytes copies a source that fits and leaves the destination's tail alone")
unittest
{
    ubyte[8] destination = 0xEE;
    assert(copyBytes(destination[], cast(const(ubyte)[]) "abc"));
    assert(destination[0 .. 3] == cast(const(ubyte)[]) "abc" && destination[3] == 0xEE);
    assert(copyBytes(destination[5 .. $], cast(const(ubyte)[]) "xyz"));
    assert(destination[5 .. $] == cast(const(ubyte)[]) "xyz");
    assert(copyBytes(destination[], null) && destination[0] == 'a');
    assert(copyBytes(null, null));
}

@("copyBytes refuses a source longer than the destination and writes nothing")
unittest
{
    ubyte[4] destination = 0xEE;
    assert(!copyBytes(destination[], cast(const(ubyte)[]) "abcde"));
    assert(destination == [0xEE, 0xEE, 0xEE, 0xEE]);
    assert(!copyBytes(null, cast(const(ubyte)[]) "a"));
}

@("copyBytes moves overlapping ranges as memmove does")
unittest
{
    ubyte[8] buffer = [1, 2, 3, 4, 5, 6, 7, 8];
    assert(copyBytes(buffer[2 .. $], buffer[0 .. 4]));
    assert(buffer == [1, 2, 1, 2, 3, 4, 7, 8]);
    assert(copyBytes(buffer[0 .. $], buffer[3 .. 6]));
    assert(buffer[0 .. 3] == [2, 3, 4]);
}
