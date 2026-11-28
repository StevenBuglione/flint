// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the Java two-stream sequence input stream. */
module flint.java.io.sequence_input_stream_contract_test;

import std.exception : assertThrown;

import flint.java.io : InputStream, OutputStream, SequenceInputStream;

import flint.java.lang : NullPointerException;

@safe:

private final class TrackingInput : InputStream
{
    const(ubyte)[] bytes;
    bool closed;
    int reads;

    this(const(ubyte)[] bytes)
    {
        this.bytes = bytes;
    }

    override int read()
    {
        ++reads;
        if (bytes.length == 0)
            return -1;
        const value = bytes[0];
        bytes = bytes[1 .. $];
        return value;
    }

    override int read(scope ubyte[] buffer, int offset, int length)
    {
        ++reads;
        const count = length < bytes.length ? length : bytes.length;
        buffer[offset .. offset + count] = bytes[0 .. count];
        bytes = bytes[count .. $];
        return count == 0 ? -1 : cast(int) count;
    }

    override int available() const
    {
        return cast(int) bytes.length;
    }

    override void close()
    {
        closed = true;
    }
}

private final class CollectingSink : OutputStream
{
    ubyte[] data;

    override void write(int value)
    {
        data ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] bytes, int offset, int length)
    {
        data ~= bytes[offset .. offset + length];
    }
}

@("SequenceInputStream reads the first stream then the second")
unittest
{
    static assert(is(SequenceInputStream : InputStream));

    auto first = new TrackingInput(cast(const(ubyte)[]) "ab");
    auto second = new TrackingInput(cast(const(ubyte)[]) "cd");
    auto sequence = new SequenceInputStream(first, second);

    assert(sequence.available() == 2);
    assert(sequence.read() == 'a');
    assert(sequence.read() == 'b');
    assert(sequence.read() == 'c');
    assert(sequence.available() == 1);
    assert(first.closed);
    assert(!second.closed);

    ubyte[3] buffer;
    assert(sequence.read(buffer[]) == 1);
    assert(buffer[0] == 'd');
    assert(sequence.read() == -1);
    assert(sequence.available() == 0);
}

@("SequenceInputStream ranged reads cross the stream boundary and skip empty streams")
unittest
{
    auto sequence = new SequenceInputStream(
            new TrackingInput(cast(const(ubyte)[]) ""),
            new TrackingInput(cast(const(ubyte)[]) "xyz"));
    ubyte[2] buffer;
    assert(sequence.read(buffer[], 0, 2) == 2);
    assert(buffer[] == [cast(ubyte) 'x', cast(ubyte) 'y']);
    assert(sequence.read(buffer[], 0, 0) == 0);
    assert(sequence.read(buffer[], 0, 2) == 1);
    assert(sequence.read(buffer[], 0, 2) == -1);
}

@("SequenceInputStream closes both streams and stays exhausted")
unittest
{
    auto first = new TrackingInput(cast(const(ubyte)[]) "a");
    auto second = new TrackingInput(cast(const(ubyte)[]) "b");
    auto sequence = new SequenceInputStream(first, second);
    sequence.close();
    assert(first.closed);
    assert(second.closed);
    assert(sequence.read() == -1);

    auto alreadyClosed = new TrackingInput(cast(const(ubyte)[]) "c");
    auto exhausted = new SequenceInputStream(alreadyClosed, new TrackingInput(cast(const(ubyte)[]) "d"));
    assert(exhausted.read() == 'c');
    assert(exhausted.read() == 'd');
    assert(exhausted.read() == -1);
    exhausted.close();
    assert(exhausted.read() == -1);
}

@("SequenceInputStream rejects a null first stream at construction")
unittest
{
    auto second = new TrackingInput(cast(const(ubyte)[]) "a");
    assertThrown!NullPointerException(new SequenceInputStream(null, second));
}

@("SequenceInputStream transferTo copies both streams and rejects a null sink")
unittest
{
    auto sequence = new SequenceInputStream(
            new TrackingInput(cast(const(ubyte)[]) "ab"),
            new TrackingInput(cast(const(ubyte)[]) "cd"));
    auto sink = new CollectingSink;
    assert(sequence.transferTo(sink) == 4);
    assert(sink.data == cast(const(ubyte)[]) "abcd");
    assert(sequence.transferTo(sink) == 0);

    auto emptied = new SequenceInputStream(
            new TrackingInput(cast(const(ubyte)[]) ""),
            new TrackingInput(cast(const(ubyte)[]) ""));
    emptied.close();
    assert(emptied.transferTo(null) == 0);
    assertThrown!NullPointerException(new SequenceInputStream(null, null).transferTo(sink));
}
