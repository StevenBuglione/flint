// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.ffi.deflate;

import core.stdc.stdlib : calloc, free;
import flint.java.util.zip.ffi.stream : ZStream, StreamStatus, StreamStep, finishStep;

@safe:

version (FlintNativeZlib)
{
    private extern (C) int deflateInit2_(ZStream*, int, int, int, int, int, const(char)*, int) @system nothrow @nogc;
    private extern (C) int deflate(ZStream*, int) @system nothrow @nogc;
    private extern (C) int deflateParams(ZStream*, int, int) @system nothrow @nogc;
    private extern (C) int deflateSetDictionary(ZStream*, const(ubyte)*, uint) @system nothrow @nogc;
    private extern (C) int deflateReset(ZStream*) @system nothrow @nogc;
    private extern (C) int deflateEnd(ZStream*) @system nothrow @nogc;
}
else
{
    static assert(0, "java-zip requires the pinned Flint zlib native recipe");
}

package(flint.java.util.zip) struct DeflateParameters
{
    int level;
    int strategy;
    bool pending;
}

package(flint.java.util.zip) struct DeflateStream
{
    private ZStream* native;

    @disable this(this);

    ~this() nothrow @nogc
    {
        close();
    }

    @property bool isOpen() const nothrow @nogc
    {
        return native !is null;
    }

    @property uint adler() const nothrow @nogc
    {
        assert(isOpen);
        return cast(uint) native.adler;
    }

    // SAFETY: Allocate a zeroed C header at its unique stable address. zlib retains
    // that address while open. Failed initialization releases the memory immediately.
    StreamStatus open(int level, bool nowrap) @trusted nothrow @nogc
    {
        if (isOpen)
            return StreamStatus.streamError;
        auto stream = cast(ZStream*) calloc(1, ZStream.sizeof);
        if (stream is null)
            return StreamStatus.noMemory;
        enum deflated = 8, defaultMemoryLevel = 8, defaultStrategy = 0;
        const status = cast(StreamStatus) deflateInit2_(stream, level, deflated, nowrap ? -15 : 15,
                defaultMemoryLevel, defaultStrategy, "1.4", ZStream.sizeof);
        if (status != StreamStatus.ok)
            free(stream);
        else
            native = stream;
        return status;
    }

    // SAFETY: The serialized live owner borrows slices with lengths bounded by int.max.
    // Pinned zlib operates synchronously. finishStep clears both pointers before return.
    @trusted nothrow @nogc StreamStep step(scope const(byte)[] input, scope byte[] output, bool finish,
            ref DeflateParameters settings)
    {
        assert(isOpen && input.length <= int.max && output.length <= int.max);
        const inputLength = cast(uint) input.length;
        const outputLength = cast(uint) output.length;
        ubyte empty;
        native.nextIn = cast(const(ubyte)*) input.ptr;
        native.availableIn = inputLength;
        native.nextOut = outputLength == 0 ? &empty : cast(ubyte*) output.ptr;
        native.availableOut = outputLength;
        StreamStatus status;
        if (settings.pending)
        {
            status = cast(StreamStatus) deflateParams(native, settings.level, settings.strategy);
            // BUF_ERROR leaves the change pending even when zlib consumes input or emits output.
            if (status == StreamStatus.ok)
                settings.pending = false;
        }
        else
        {
            enum noFlush = 0, finishFlush = 4;
            status = cast(StreamStatus) deflate(native, finish ? finishFlush : noFlush);
        }
        return finishStep(*native, inputLength, outputLength, status);
    }

    // SAFETY: The dictionary is read during this call. Native retained history
    // belongs to the live stream, and does not borrow the caller's slice.
    StreamStatus setDictionary(scope const(byte)[] dictionary) @trusted nothrow @nogc
    {
        assert(isOpen && dictionary.length <= int.max);
        ubyte empty;
        const data = dictionary.length == 0 ? &empty : cast(const(ubyte)*) dictionary.ptr;
        return cast(StreamStatus) deflateSetDictionary(native, data, cast(uint) dictionary.length);
    }

    // SAFETY: Only the serialized live owner can reset its native stream.
    StreamStatus reset() @trusted nothrow @nogc
    {
        assert(isOpen);
        return cast(StreamStatus) deflateReset(native);
    }

    // SAFETY: Clear the unique owner before ending the stream and freeing its header.
    // DeflateEnd releases native state even if the stream ended before finish.
    StreamStatus close() @trusted nothrow @nogc
    {
        auto stream = native;
        if (stream is null)
            return StreamStatus.ok;
        native = null;
        const status = cast(StreamStatus) deflateEnd(stream);
        free(stream);
        return status;
    }
}
