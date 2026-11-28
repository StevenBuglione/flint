// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java byte-array input stream. */
module flint.java.io.byte_array_input_contract_test;

import flint.java.io : ByteArrayInputStream, InputStream, OutputStream;

import std.exception : assertThrown;

import flint.java.lang : NullPointerException;

@safe:

@("ByteArrayInputStream reads the shared backing bytes as unsigned octets")
unittest
{
    ubyte[] bytes = [0x7F, 0x80, 0x00];
    auto input = new ByteArrayInputStream(bytes);
    InputStream stream = input;

    assert(input.available() == 3);
    assert(stream.read() == 0x7F);
    assert(input.available() == 2);

    bytes[2] = 0xFF;
    assert(stream.read() == 0x80);
    assert(input.available() == 1);
    stream.close();
    assert(stream.read() == 0xFF);
    assert(input.available() == 0);
    assert(stream.read() == -1);
    assert(stream.read() == -1);
}

@("ByteArrayInputStream treats a null slice as an empty buffer under R26")
unittest
{
    const(ubyte)[] absent;
    auto input = new ByteArrayInputStream(absent);
    assert(input.available() == 0);
    assert(input.read() == -1);

    ubyte[] source = [0];
    auto empty = new ByteArrayInputStream(source[0 .. 0]);
    assert(empty.available() == 0);
    assert(empty.read() == -1);
}

private final class RangedProbe : ByteArrayInputStream
{
    this(const(ubyte)[] bytes, int offset, int length)
    {
        super(bytes, offset, length);
    }

    int fieldCount() const pure nothrow @nogc
    {
        return count;
    }

    size_t backingLength() const pure nothrow @nogc
    {
        return buf.length;
    }
}

private final class CollectingSink : OutputStream
{
    ubyte[] data;
    int rangedWrites;

    override void write(int value)
    {
        data ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] bytes, int offset, int length)
    {
        ++rangedWrites;
        data ~= bytes[offset .. offset + length];
    }
}

@("ByteArrayInputStream ranges reads and opens the mark at the constructor offset")
unittest
{
    const(ubyte)[] bytes = [10, 11, 12, 13, 14];
    auto input = new RangedProbe(bytes, 1, 2);

    assert(input.fieldCount() == 3);
    assert(input.backingLength() == 5);
    assert(input.available() == 2);
    assert(input.read() == 11);
    assert(input.read() == 12);
    assert(input.read() == -1);

    input.reset();
    assert(input.available() == 2);
    assert(input.read() == 11);
}

@("ByteArrayInputStream marks, resets and reports mark support")
unittest
{
    ubyte[] bytes = [1, 2, 3, 4];
    auto input = new ByteArrayInputStream(bytes);
    assert(input.markSupported());
    assert(input.read() == 1);
    input.mark(1);
    assert(input.read() == 2);
    assert(input.read() == 3);
    input.reset();
    assert(input.available() == 3);
    assert(input.read() == 2);
}

@("ByteArrayInputStream readAllBytes copies the remainder and advances to the end")
unittest
{
    ubyte[] bytes = [5, 6, 7, 8];
    auto input = new ByteArrayInputStream(bytes);
    assert(input.read() == 5);
    assert(input.readAllBytes() == [cast(ubyte) 6, cast(ubyte) 7, cast(ubyte) 8]);
    assert(input.available() == 0);
    assert(input.read() == -1);
    assert(input.readAllBytes().length == 0);
}

@("ByteArrayInputStream ranged read returns -1 at EOF before checking for a zero length")
unittest
{
    ubyte[] bytes = [9];
    auto input = new ByteArrayInputStream(bytes);
    ubyte[1] scratch;
    assert(input.read(scratch[], 0, 1) == 1);
    assert(scratch[0] == 9);
    assert(input.read(scratch[], 0, 0) == -1);
    assert(input.readNBytes(scratch[], 0, 0) == 0);
}

@("ByteArrayInputStream transferTo copies the remainder in place and keeps the stream open")
unittest
{
    ubyte[] bytes = [1, 2, 3, 4, 5];
    auto input = new ByteArrayInputStream(bytes);
    auto sink = new CollectingSink;
    assert(input.read() == 1);
    assert(input.transferTo(sink) == 4);
    assert(sink.rangedWrites == 1);
    assert(sink.data == [cast(ubyte) 2, cast(ubyte) 3, cast(ubyte) 4, cast(ubyte) 5]);
    assert(input.available() == 0);
    assert(input.transferTo(sink) == 0);
    assert(input.transferTo(null) == 0);
    assert(sink.rangedWrites == 1);

    auto one = new ByteArrayInputStream([cast(ubyte) 7]);
    assertThrown!NullPointerException(one.transferTo(null));
    assert(one.available() == 1);
}
