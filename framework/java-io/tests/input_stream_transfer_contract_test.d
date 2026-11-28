// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the Java bounded reads and stream transfer. */
module flint.java.io.input_stream_transfer_contract_test;

import flint.java.io : ByteArrayInputStream, OutputStream;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException;
import std.exception : assertThrown;

@safe:

private final class RecordingSink : OutputStream
{
    ubyte[] bytes;
    int rangedWrites;

    override void write(int value)
    {
        bytes ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] data, int offset, int count)
    {
        ++rangedWrites;
        super.write(data, offset, count);
    }
}

@("InputStream.readNBytes(int) reads at most the requested count and stops at end of stream")
unittest
{
    auto stream = new ByteArrayInputStream(cast(const(ubyte)[]) "hello");
    assert(stream.readNBytes(2) == cast(const(ubyte)[]) "he");
    assert(stream.available() == 3);
    assert(stream.readNBytes(10) == cast(const(ubyte)[]) "llo");
    assert(stream.readNBytes(1).length == 0);
}

@("InputStream.readNBytes(int) accepts zero and rejects a negative length")
unittest
{
    auto stream = new ByteArrayInputStream(cast(const(ubyte)[]) "x");
    assert(stream.readNBytes(0).length == 0);
    assert(stream.available() == 1);
    assertThrown!IllegalArgumentException(stream.readNBytes(-1));
}

@("InputStream.readNBytes(range) fills the caller range and returns zero at end of stream")
unittest
{
    auto stream = new ByteArrayInputStream(cast(const(ubyte)[]) "abcdef");
    ubyte[8] buffer;
    assert(stream.readNBytes(buffer[], 1, 4) == 4);
    assert(buffer[1 .. 5] == cast(const(ubyte)[]) "abcd");
    assert(stream.readNBytes(buffer[], 0, 8) == 2);
    assert(buffer[0 .. 2] == cast(const(ubyte)[]) "ef");
    assert(stream.readNBytes(buffer[], 0, 0) == 0);
    assert(stream.readNBytes(buffer[], 0, 2) == 0);
}

@("InputStream.readNBytes(range) validates the range without overflow")
unittest
{
    auto stream = new ByteArrayInputStream(cast(const(ubyte)[]) "x");
    ubyte[4] buffer;
    assertThrown!IndexOutOfBoundsException(stream.readNBytes(buffer[], 5, 0));
    assertThrown!IndexOutOfBoundsException(stream.readNBytes(buffer[], -1, 1));
    assertThrown!IndexOutOfBoundsException(stream.readNBytes(buffer[], 0, -1));
    assertThrown!IndexOutOfBoundsException(stream.readNBytes(buffer[], 3, int.max));
    assert(stream.available() == 1);
}

@("InputStream.transferTo copies every remaining byte through the ranged sink write")
unittest
{
    auto stream = new ByteArrayInputStream(cast(const(ubyte)[]) "abcdef");
    auto sink = new RecordingSink;
    assert(stream.transferTo(sink) == 6);
    assert(sink.bytes == cast(const(ubyte)[]) "abcdef");
    assert(sink.rangedWrites >= 1);
    assert(stream.available() == 0);
    assert(stream.transferTo(sink) == 0);
}

@("InputStream.transferTo rejects a null sink before reading")
unittest
{
    auto stream = new ByteArrayInputStream(cast(const(ubyte)[]) "x");
    assertThrown!NullPointerException(stream.transferTo(null));
    assert(stream.available() == 1);
}
