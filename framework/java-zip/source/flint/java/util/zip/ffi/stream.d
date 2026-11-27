// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.ffi.stream;

import core.stdc.config : c_ulong;

@safe:

package(flint.java.util.zip)
{
    enum StreamStatus : int
    {
        ok = 0,
        finished = 1,
        needsDictionary = 2,
        streamError = -2,
        dataError = -3,
        noMemory = -4,
        noProgress = -5,
        versionError = -6,
    }

    struct StreamStep
    {
        StreamStatus status;
        int read;
        int written;
    }
}

private alias Allocate = extern (C) void* function(void*, uint, uint) nothrow @nogc;
private alias Release = extern (C) void function(void*, void*) nothrow @nogc;

package(flint.java.util.zip) struct ZStream
{
    const(ubyte)* nextIn;
    uint availableIn;
    c_ulong totalIn;
    ubyte* nextOut;
    uint availableOut;
    c_ulong totalOut;
    const(char)* message;
    void* state;
    Allocate allocate;
    Release release;
    void* opaque;
    int dataType;
    c_ulong adler;
    c_ulong reserved;
}

package(flint.java.util.zip) StreamStep finishStep(ref ZStream stream, uint inputLength,
        uint outputLength, StreamStatus status) nothrow @nogc
{
    const read = cast(int)(inputLength - stream.availableIn);
    const written = cast(int)(outputLength - stream.availableOut);
    stream.nextIn = null;
    stream.nextOut = null;
    stream.availableIn = stream.availableOut = 0;
    return StreamStep(status, read, written);
}

// zlib uses memcpy for stored blocks. Do not expose overlapping caller buffers
// to the same step or overwrite input that remains pending after it.
package(flint.java.util.zip) const(byte)[] isolateInput(const(byte)[] input, scope byte[] output)
{
    if (!overlaps(input, output))
        return input;
    auto owned = new byte[input.length];
    owned[] = input;
    return owned;
}

// SAFETY: Convert live buffer addresses to unsigned integers for comparison only.
// No pointer arithmetic or dereferences occur. Subtraction uses the larger address.
private bool overlaps(scope const(byte)[] input, scope byte[] output) @trusted nothrow @nogc
{
    if (input.length == 0 || output.length == 0)
        return false;
    const inputAddress = cast(size_t) input.ptr;
    const outputAddress = cast(size_t) output.ptr;
    return inputAddress < outputAddress ? outputAddress - inputAddress < input.length
        : inputAddress - outputAddress < output.length;
}
