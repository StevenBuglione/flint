// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java output stream. */
module flint.java.io.output_stream_contract_test;

import flint.java.io : ByteArrayOutputStream, OutputStream;
import flint.java.lang : IndexOutOfBoundsException;
import std.exception : assertThrown;

@safe:

private final class RecordingSink : OutputStream
{
    ubyte[] bytes;

    override void write(int value)
    {
        bytes ~= cast(ubyte) value;
    }
}

@("OutputStream leaves resource-free sinks writable after default flush and close")
unittest
{
    static assert(__traits(isAbstractClass, OutputStream));

    auto sink = new RecordingSink;
    OutputStream stream = sink;
    stream.write(0x1FF);
    stream.flush();
    stream.write(0x180);
    stream.close();
    stream.write(-2);

    assert(sink.bytes == [cast(ubyte) 0xFF, cast(ubyte) 0x80, cast(ubyte) 0xFE]);
}

private final class BulkSink : OutputStream
{
    int[] values;
    int wholeWrites;

    override void write(int value)
    {
        values ~= value;
    }

    override void write(scope const(ubyte)[] bytes)
    {
        ++wholeWrites;
        super.write(bytes);
    }
}

private final class RangedBuffer : ByteArrayOutputStream
{
    int rangedWrites;
    ubyte[] observed;

    override void write(scope const(ubyte)[] bytes, int offset, int count)
    {
        ++rangedWrites;
        observed = bytes[offset .. offset + count].dup;
    }
}

@("OutputStream whole-array write dispatches to the ranged override")
unittest
{
    auto buffer = new RangedBuffer;
    OutputStream stream = buffer;
    const ubyte[] bytes = [0, 0x80, 0xFF];
    stream.write(bytes);
    assert(buffer.rangedWrites == 1, "whole-array write must reach the ranged override");
    assert(buffer.observed == bytes);
}

@("OutputStream ranged write calls the signed byte sink without dispatching to the whole-array overload")
unittest
{
    auto sink = new BulkSink;
    OutputStream stream = sink;
    const ubyte[] bytes = [0, 0x80, 0xFF];
    stream.write(bytes, 1, 2);
    stream.write(bytes, 3, 0);
    assert(sink.wholeWrites == 0, "ranged write must bypass the whole-array override");
    assert(sink.values == [-128, -1], "Java bytes are sign-extended before write(int)");
}

@("Bulk stream writes validate ranges without overflow and accept empty D slices")
unittest
{
    foreach (stream; [cast(OutputStream) new BulkSink, new ByteArrayOutputStream])
    {
        const ubyte[] bytes = [1, 2, 3];
        assertThrown!IndexOutOfBoundsException(stream.write(bytes, -1, 1));
        assertThrown!IndexOutOfBoundsException(stream.write(bytes, 0, -1));
        assertThrown!IndexOutOfBoundsException(stream.write(bytes, 2, int.max));
        assertThrown!IndexOutOfBoundsException(stream.write(bytes, 4, 0));
        assertThrown!IndexOutOfBoundsException(stream.write(null, 1, 0));
        stream.write(null);
        stream.write(null, 0, 0);
    }
}

@("ByteArrayOutputStream appends exactly the selected range")
unittest
{
    auto buffer = new ByteArrayOutputStream;
    OutputStream stream = buffer;
    const ubyte[] bytes = [0, 0x80, 0xFF];
    stream.write(bytes, 1, 2);
    stream.write(bytes, 3, 0);
    assert(buffer.toByteArray() == bytes[1 .. $]);
}
