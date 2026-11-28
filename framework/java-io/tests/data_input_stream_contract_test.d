// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's data input stream. */
module flint.java.io.data_input_stream_contract_test;

import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream, DataInputStream,
    DataOutputStream, EOFException, IOException, InputStream, UTFDataFormatException;
import flint.java.lang : IndexOutOfBoundsException;
import std.exception : assertThrown, collectException;

@safe:

private DataInputStream over(const(ubyte)[] bytes)
{
    return new DataInputStream(new ByteArrayInputStream(bytes));
}

private final class ClosingInput : InputStream
{
    bool closed;

    override int read()
    {
        if (closed)
            throw new IOException("Stream closed");
        return -1;
    }

    override int read(scope ubyte[] buffer, int offset, int length)
    {
        if (closed)
            throw new IOException("Stream closed");
        return -1;
    }

    override void close()
    {
        closed = true;
    }
}

@("DataInputStream operations fail after close when the wrapped stream does")
unittest
{
    auto source = new ClosingInput;
    auto input = new DataInputStream(source);
    input.close();
    assert(source.closed);

    assertThrown!IOException(input.readUnsignedByte());
    ubyte[1] one;
    assertThrown!IOException(input.readFully(one));
}

@("DataInputStream reads each primitive in Java's big-endian form")
unittest
{
    ubyte[] bytes = [
        0x01, // boolean true
        0xFF, // byte -1
        0x80, // unsigned byte 128
        0x12, 0x34, // short 0x1234
        0xAB, 0xCD, // char 0xABCD
        0x12, 0x34, 0x56, 0x78, // int 0x12345678
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // long
        0x3F, 0xC0, 0x00, 0x00, // float 1.5
        0x40, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // double 2.25
    ];
    auto input = over(bytes);

    assert(input.readBoolean());
    assert(input.readByte() == -1);
    assert(input.readUnsignedByte() == 0x80);
    assert(input.readShort() == cast(short) 0x1234);
    assert(input.readChar() == cast(wchar) 0xABCD);
    assert(input.readInt() == 0x12345678);
    assert(input.readLong() == 0x0102_0304_0506_0708L);
    assert(input.readFloat() == 1.5f);
    assert(input.readDouble() == 2.25);
    assert(input.read() == -1);
}

@("DataInputStream reads values written by DataOutputStream")
unittest
{
    auto sink = new ByteArrayOutputStream;
    auto output = new DataOutputStream(sink);
    output.writeBoolean(true);
    output.writeByte(0x7F);
    output.writeShort(-2);
    output.writeChar(0xABCD);
    output.writeInt(-123_456);
    output.writeLong(0x0102_0304_0506_0708L);
    output.writeFloat(1.5f);
    output.writeDouble(-2.25);
    output.writeUTF("h\u00E9llo \U0001F600");

    auto input = over(sink.toByteArray());
    assert(input.readBoolean());
    assert(input.readByte() == 0x7F);
    assert(input.readShort() == -2);
    assert(input.readChar() == cast(wchar) 0xABCD);
    assert(input.readInt() == -123_456);
    assert(input.readLong() == 0x0102_0304_0506_0708L);
    assert(input.readFloat() == 1.5f);
    assert(input.readDouble() == -2.25);
    assert(input.readUTF() == "h\u00E9llo \U0001F600");
}

@("DataInputStream readFully fills the range or reports the end")
unittest
{
    auto input = over([1, 2, 3, 4]);

    ubyte[2] first;
    input.readFully(first);
    assert(first[] == [ubyte(1), ubyte(2)]);

    ubyte[3] rest;
    assertThrown!EOFException(input.readFully(rest));
    assert(rest[0 .. 2] == [ubyte(3), ubyte(4)]);

    ubyte[1] one;
    assertThrown!IndexOutOfBoundsException(input.readFully(one, -1, 1));
    assertThrown!IndexOutOfBoundsException(input.readFully(one, 0, 2));
}

@("DataInputStream reports the end of the stream for a primitive")
unittest
{
    auto input = over([]);
    assertThrown!EOFException(input.readUnsignedByte());
    assertThrown!EOFException(input.readShort());
    assertThrown!EOFException(input.readInt());
    assertThrown!EOFException(input.readLong());
    assertThrown!EOFException(input.readFloat());
    assertThrown!EOFException(input.readDouble());
}

@("DataInputStream skipBytes reports the count actually skipped")
unittest
{
    auto input = over([1, 2, 3, 4, 5]);
    assert(input.skipBytes(3) == 3);
    assert(input.read() == 4);
    assert(input.skipBytes(10) == 1);
    assert(input.read() == -1);
}

@("DataInputStream read and readFully delegate to the wrapped stream")
unittest
{
    auto input = over([9, 8, 7, 6]);
    ubyte[] buffer = new ubyte[2];
    assert(input.read(buffer) == 2);
    assert(buffer == [ubyte(9), ubyte(8)]);
    assert(input.read(buffer, 0, 2) == 2);
    assert(buffer == [ubyte(7), ubyte(6)]);
}

@("DataInputStream readUTF round-trips modified UTF-8")
unittest
{
    foreach (text; ["", "A", "\u0000", "\u00FF", "\U0001F600"])
    {
        auto sink = new ByteArrayOutputStream;
        auto output = new DataOutputStream(sink);
        output.writeUTF(text);
        auto input = over(sink.toByteArray());
        assert(input.readUTF() == text);
        auto second = over(sink.toByteArray());
        assert(DataInputStream.readUTF(second) == text);
    }
}

@("DataInputStream readUTF rejects malformed modified UTF-8 with a message")
unittest
{
    auto stray = over([0x00, 0x01, 0x80]);
    auto strayFailure = collectException!UTFDataFormatException(stray.readUTF());
    assert(strayFailure !is null);
    assert(strayFailure.getMessage() !is null);

    auto partial = over([0x00, 0x01, 0xC0]);
    auto partialFailure = collectException!UTFDataFormatException(partial.readUTF());
    assert(partialFailure !is null);
    assert(partialFailure.getMessage() == "malformed input: partial character at end");

    auto partialThree = over([0x00, 0x02, 0xE0, 0x80]);
    auto partialThreeFailure = collectException!UTFDataFormatException(partialThree.readUTF());
    assert(partialThreeFailure !is null);
    assert(partialThreeFailure.getMessage() == "malformed input: partial character at end");
}
