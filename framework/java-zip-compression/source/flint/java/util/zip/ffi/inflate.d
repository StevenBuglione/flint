// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.ffi.inflate;

import core.stdc.stdlib : calloc, free;
import core.stdc.string : strlen;
import flint.java.util.zip.ffi.stream : ZStream, StreamStatus, StreamStep, finishStep;

@safe:

version (FlintNativeZlib)
{
    private extern (C) int inflateInit2_(ZStream*, int, const(char)*, int) @system nothrow @nogc;
    private extern (C) int inflate(ZStream*, int) @system nothrow @nogc;
    private extern (C) int inflateSetDictionary(ZStream*, const(ubyte)*, uint) @system nothrow @nogc;
    private extern (C) int inflateReset(ZStream*) @system nothrow @nogc;
    private extern (C) int inflateEnd(ZStream*) @system nothrow @nogc;
}
else
{
    static assert(0, "java-zip requires the pinned Flint zlib native recipe");
}

package(flint.java.util.zip) struct InflateStream
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

    // SAFETY: Allocate zeroed, properly aligned storage for the stream. zlib sees
    // its stable address until the sole owner ends it. Failed initialization frees it.
    StreamStatus open(bool nowrap) @trusted nothrow @nogc
    {
        if (isOpen)
            return StreamStatus.streamError;
        auto stream = cast(ZStream*) calloc(1, ZStream.sizeof);
        if (stream is null)
            return StreamStatus.noMemory;
        const status = cast(StreamStatus) inflateInit2_(stream, nowrap ? -15 : 15, "1.4", ZStream.sizeof);
        if (status != StreamStatus.ok)
            free(stream);
        else
            native = stream;
        return status;
    }

    // SAFETY: The serialized live owner borrows slices with lengths bounded by int.max.
    // Pinned zlib operates synchronously. finishStep clears both pointers before return.
    StreamStep step(scope const(byte)[] input, scope byte[] output) @trusted nothrow @nogc
    {
        assert(isOpen && input.length <= int.max && output.length <= int.max);
        const inputLength = cast(uint) input.length;
        const outputLength = cast(uint) output.length;
        ubyte empty;
        native.nextIn = cast(const(ubyte)*) input.ptr;
        native.availableIn = inputLength;
        native.nextOut = outputLength == 0 ? &empty : cast(ubyte*) output.ptr;
        native.availableOut = outputLength;
        enum partialFlush = 1;
        const status = cast(StreamStatus) inflate(native, partialFlush);
        return finishStep(*native, inputLength, outputLength, status);
    }

    // SAFETY: This call copies the dictionary into the uniquely owned stream.
    // zlib never retains its source pointer after the synchronous call.
    StreamStatus setDictionary(scope const(byte)[] dictionary) @trusted nothrow @nogc
    {
        assert(isOpen && dictionary.length <= int.max);
        ubyte empty;
        const data = dictionary.length == 0 ? &empty : cast(const(ubyte)*) dictionary.ptr;
        return cast(StreamStatus) inflateSetDictionary(native, data, cast(uint) dictionary.length);
    }

    // SAFETY: Only the live, serialized native owner may reset its stream.
    StreamStatus reset() @trusted nothrow @nogc
    {
        assert(isOpen);
        return cast(StreamStatus) inflateReset(native);
    }

    // SAFETY: zlib exposes a null or NUL-terminated error string. The caller
    // serializes access to the live stream, and the returned D string owns its bytes.
    @trusted string message()
    {
        assert(isOpen);
        const text = native.message;
        if (text is null)
            return null;
        auto owned = new char[strlen(text)];
        owned[] = text[0 .. owned.length];
        return cast(string) owned;
    }

    // SAFETY: Remove the unique pointer before ending the native stream and
    // freeing its header. Subsequent end or destruction sees null.
    StreamStatus close() @trusted nothrow @nogc
    {
        auto stream = native;
        if (stream is null)
            return StreamStatus.ok;
        native = null;
        const status = cast(StreamStatus) inflateEnd(stream);
        free(stream);
        return status;
    }
}
