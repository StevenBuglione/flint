// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java byte-array output stream. */
module flint.java.io.byte_array_output_contract_test;

import flint.java.io : ByteArrayOutputStream, OutputStream;

import std.exception : assertThrown;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException;

@safe:

@("ByteArrayOutputStream keeps the low eight bits of each integer write")
unittest
{
    static assert(is(ByteArrayOutputStream : OutputStream));

    auto output = new ByteArrayOutputStream;
    assert(output.size() == 0 && output.toByteArray().length == 0);

    OutputStream sink = output;
    sink.write(0x1FF);
    sink.write(-2);
    assert(output.size() == 2);
    assert(output.toByteArray() == [cast(ubyte) 0xFF, cast(ubyte) 0xFE]);
}

@("ByteArrayOutputStream returns detached byte copies and can be reused after reset")
unittest
{
    auto output = new ByteArrayOutputStream;
    output.write(0xFF);
    output.write(0xFE);

    auto snapshot = output.toByteArray();
    snapshot[0] = 0;
    assert(output.toByteArray()[0] == 0xFF && output.size() == 2);

    output.reset();
    assert(output.size() == 0 && output.toByteArray().length == 0);
    output.write(0x7F);
    assert(output.toByteArray() == [cast(ubyte) 0x7F]);
    assert(snapshot == [cast(ubyte) 0, cast(ubyte) 0xFE]);
}

private final class CapturingSink : OutputStream
{
    ubyte[] data;
    int calls;

    override void write(int value)
    {
        ++calls;
        data ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] bytes, int offset, int length)
    {
        ++calls;
        data ~= bytes[offset .. offset + length];
    }
}

private final class CapacityProbe : ByteArrayOutputStream
{
    this(int size)
    {
        super(size);
    }

    int fieldCount() const pure nothrow @nogc
    {
        return count;
    }

    size_t capacity() const pure nothrow @nogc
    {
        return buf.length;
    }
}

@("ByteArrayOutputStream starts with Java's 32-byte buffer and explicit capacities")
unittest
{
    auto plain = new CapacityProbe(0);
    assert(plain.capacity() == 0 && plain.fieldCount() == 0);
    plain.write(1);
    assert(plain.fieldCount() == 1 && plain.capacity() >= 1);

    auto sized = new CapacityProbe(4);
    assert(sized.capacity() == 4);
    sized.write(1);
    assert(sized.fieldCount() == 1 && sized.capacity() == 4);
    sized.write([cast(ubyte) 2, cast(ubyte) 3, cast(ubyte) 4, cast(ubyte) 5]);
    assert(sized.size() == 5 && sized.capacity() > 4);
    assert(sized.toByteArray() == [1, 2, 3, 4, 5]);
}

@("ByteArrayOutputStream rejects a negative initial capacity")
unittest
{
    assertThrown!IllegalArgumentException(new ByteArrayOutputStream(-1));
    assertThrown!IllegalArgumentException(new ByteArrayOutputStream(int.min));
}

@("ByteArrayOutputStream writeBytes, ranged writes and writeTo keep the accumulated bytes")
unittest
{
    auto output = new ByteArrayOutputStream;
    auto sink = new CapturingSink;

    output.writeBytes([cast(ubyte) 10, cast(ubyte) 11, cast(ubyte) 12]);
    output.write([cast(ubyte) 20, cast(ubyte) 21, cast(ubyte) 22, cast(ubyte) 23], 1, 2);
    assert(output.toByteArray() == [10, 11, 12, 21, 22]);

    output.writeTo(sink);
    assert(sink.calls == 1);
    assert(sink.data == [10, 11, 12, 21, 22]);
    assert(output.size() == 5);

    output.reset();
    assert(output.size() == 0 && output.toByteArray().length == 0);
    output.write(99);
    assert(output.toByteArray() == [cast(ubyte) 99]);
}

@("ByteArrayOutputStream writeTo rejects a null sink and checks the write range")
unittest
{
    auto output = new ByteArrayOutputStream;
    assertThrown!NullPointerException(output.writeTo(null));

    assertThrown!IndexOutOfBoundsException(output.write([cast(ubyte) 1, cast(ubyte) 2], 1, 2));
    assertThrown!IndexOutOfBoundsException(output.write([cast(ubyte) 1], -1, 1));
    assert(output.size() == 0);
}
