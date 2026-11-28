// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's data output stream. */
module flint.java.io.data_output_stream_contract_test;

import flint.java.io : DataOutputStream, OutputStream, UTFDataFormatException;
import std.exception : assertThrown;

@safe:

private final class RecordingOutput : OutputStream
{
    ubyte[] data;
    int flushes;

    override void write(int value)
    {
        data ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] buffer, int offset, int length)
    {
        data ~= buffer[offset .. offset + length];
    }

    override void flush()
    {
        ++flushes;
    }
}

@("DataOutputStream writes each primitive in Java's big-endian form")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new DataOutputStream(sink);

    output.writeBoolean(true);
    output.writeBoolean(false);
    output.writeByte(0x1FF);
    assert(sink.data == [1, 0, 0xFF]);
    assert(output.size() == 3);

    output.writeShort(0x1234);
    output.writeChar(0xABCD);
    assert(sink.data[3 .. 7] == [0x12, 0x34, 0xAB, 0xCD]);
    assert(output.size() == 7);

    output.writeInt(0x12345678);
    assert(sink.data[7 .. 11] == [0x12, 0x34, 0x56, 0x78]);
    assert(output.size() == 11);

    output.writeLong(0x0102030405060708L);
    assert(sink.data[11 .. 19] == [1, 2, 3, 4, 5, 6, 7, 8]);
    assert(output.size() == 19);

    output.writeFloat(1.0f);
    assert(sink.data[19 .. 23] == [0x3F, 0x80, 0x00, 0x00]);
    assert(output.size() == 23);

    output.writeDouble(1.0);
    assert(sink.data[23 .. 31] == [0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    assert(output.size() == 31);
}

@("DataOutputStream canonicalises NaN bits like Java")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new DataOutputStream(sink);

    output.writeFloat(float.nan);
    assert(sink.data == [0x7F, 0xC0, 0x00, 0x00]);

    sink.data = null;
    output.writeDouble(double.nan);
    assert(sink.data == [0x7F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
}

@("DataOutputStream counts bytes written through the inherited write")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new DataOutputStream(sink);

    ubyte[] three = [1, 2, 3];
    output.write(three);
    assert(sink.data == [1, 2, 3]);
    assert(output.size() == 3);

    ubyte[] padded = [9, 4, 5, 9];
    output.write(padded, 1, 2);
    assert(sink.data == [1, 2, 3, 4, 5]);
    assert(output.size() == 5);

    output.flush();
    assert(sink.flushes == 1);
}

@("DataOutputStream writes bytes and chars from UTF-16 code units")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new DataOutputStream(sink);

    output.writeBytes("AB");
    assert(sink.data == [0x41, 0x42]);
    assert(output.size() == 2);

    output.writeBytes("\u00FF");
    assert(sink.data[2 .. 3] == [0xFF]);
    assert(output.size() == 3);

    output.writeBytes("\U0001F600");
    assert(sink.data[3 .. 5] == [0x3D, 0x00]);
    assert(output.size() == 5);

    sink.data = null;
    output.writeChars("A");
    assert(sink.data == [0x00, 0x41]);

    sink.data = null;
    output.writeChars("\u00FF");
    assert(sink.data == [0x00, 0xFF]);

    sink.data = null;
    output.writeChars("\U0001F600");
    assert(sink.data == [0xD8, 0x3D, 0xDE, 0x00]);
}

@("DataOutputStream writes modified UTF-8 with a two-byte length")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new DataOutputStream(sink);

    output.writeUTF("A");
    assert(sink.data == [0x00, 0x01, 0x41]);
    assert(output.size() == 3);

    sink.data = null;
    output.writeUTF("\u0000");
    assert(sink.data == [0x00, 0x02, 0xC0, 0x80]);

    sink.data = null;
    output.writeUTF("\u00FF");
    assert(sink.data == [0x00, 0x02, 0xC3, 0xBF]);

    sink.data = null;
    output.writeUTF("\U0001F600");
    assert(sink.data == [0x00, 0x06, 0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80]);
}

@("DataOutputStream rejects modified UTF-8 longer than 65535 bytes")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new DataOutputStream(sink);

    output.writeByte(7);
    const before = output.size();
    string text = "A";
    while (text.length < 65_536)
        text ~= text;
    assert(text.length == 65_536);
    assertThrown!UTFDataFormatException(output.writeUTF(text));
    assert(output.size() == before);
    assert(sink.data == [7]);
}
