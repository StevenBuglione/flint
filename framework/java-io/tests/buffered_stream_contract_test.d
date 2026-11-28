// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's buffered input and output streams. */
module flint.java.io.buffered_stream_contract_test;

import flint.java.io : BufferedInputStream, BufferedOutputStream, IOException, InputStream, OutputStream;
import flint.java.lang : IndexOutOfBoundsException;
import std.exception : assertThrown, collectException;

@safe:

private final class RecordingInput : InputStream
{
    ubyte[] data;
    size_t position;
    int rangedCalls;
    int singleReads;
    bool closed;
    int reportedAvailable = -1;
    int rangedLimit;

    override int read()
    {
        ++singleReads;
        return position < data.length ? data[position++] : -1;
    }

    override int read(scope ubyte[] buffer, int offset, int length)
    {
        ++rangedCalls;
        int wanted = length;
        if (rangedLimit > 0 && wanted > rangedLimit)
            wanted = rangedLimit;
        int count;
        while (count < wanted && position < data.length)
            buffer[cast(size_t) offset + count] = data[position++], ++count;
        return count;
    }

    override int available()
    {
        return reportedAvailable >= 0 ? reportedAvailable : cast(int)(data.length - position);
    }

    override void close()
    {
        closed = true;
    }
}

private final class RecordingOutput : OutputStream
{
    ubyte[] data;
    int flushes;
    int closes;

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

    override void close()
    {
        ++closes;
    }
}

@("BufferedInputStream reads, marks, resets and grows the buffer across a mark")
unittest
{
    auto source = new RecordingInput;
    source.data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    auto input = new BufferedInputStream(source, 4);

    assert(input.markSupported());
    assert(input.read() == 0);
    assert(input.read() == 1);
    assert(input.read() == 2);
    assert(input.read() == 3);

    input.mark(100);
    assert(input.read() == 4);
    assert(input.read() == 5);
    assert(input.read() == 6);
    assert(input.read() == 7);

    input.reset();
    assert(input.read() == 4);
    assert(input.read() == 5);

    assert(input.available() == 4);
    assert(input.skip(1) == 1);
    assert(input.read() == 7);
    assert(input.read() == 8);
    assert(input.read() == 9);
    assert(input.read() == -1);
}

@("BufferedInputStream reads a large request straight through without a mark")
unittest
{
    auto source = new RecordingInput;
    source.data = [0, 1, 2, 3, 4, 5, 6, 7];
    auto input = new BufferedInputStream(source, 4);

    ubyte[] destination = new ubyte[8];
    assert(input.read(destination) == 8);
    assert(destination == [0, 1, 2, 3, 4, 5, 6, 7]);
    assert(source.rangedCalls == 1);
    assert(source.singleReads == 0);
}

@("BufferedInputStream stops a ranged read when the wrapped stream cannot continue")
unittest
{
    auto source = new RecordingInput;
    source.data = [10, 11, 12];
    source.rangedLimit = 1;
    source.reportedAvailable = 0;
    auto input = new BufferedInputStream(source, 4);

    ubyte[] destination = new ubyte[3];
    assert(input.read(destination) == 1);
    assert(destination[0] == 10);
    assert(input.read(destination[1 .. 3]) == 1);
    assert(destination[1] == 11);
}

@("BufferedInputStream reports a closed stream after close and closes once")
unittest
{
    auto source = new RecordingInput;
    source.data = [1, 2];
    auto input = new BufferedInputStream(source, 4);

    assert(input.read() == 1);
    input.close();
    assert(source.closed);
    input.close();
    assert(source.closed);

    assertThrown!IOException(input.read());
    assertThrown!IOException(input.reset());
    assertThrown!IOException(input.available());
    assertThrown!IOException(input.skip(1));
}

@("BufferedInputStream reset without a mark fails")
unittest
{
    auto source = new RecordingInput;
    source.data = [1];
    auto input = new BufferedInputStream(source, 4);

    assertThrown!IOException(input.reset());
}

@("BufferedInputStream skip delegates to the wrapped stream without a mark")
unittest
{
    auto source = new RecordingInput;
    source.data = [1, 2, 3, 4, 5];
    auto input = new BufferedInputStream(source, 4);

    assert(input.skip(2) == 2);
    assert(source.position == 2);
    assert(input.read() == 3);
}

@("BufferedOutputStream buffers writes and flushes them in order")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new BufferedOutputStream(sink, 4);

    output.write(1);
    output.write(2);
    output.write(3);
    output.write(4);
    assert(sink.data.length == 0);

    output.write(5);
    assert(sink.data == [1, 2, 3, 4]);

    output.flush();
    assert(sink.data == [1, 2, 3, 4, 5]);
    assert(sink.flushes == 1);

    output.close();
    assert(sink.closes == 1);
    output.close();
    assert(sink.closes == 1);
}

@("BufferedOutputStream passes a write at least the buffer size straight through")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new BufferedOutputStream(sink, 4);

    ubyte[] exact = [1, 2, 3, 4];
    output.write(exact);
    assert(sink.data == [1, 2, 3, 4]);

    ubyte[] larger = [5, 6, 7, 8, 9];
    output.write(larger);
    assert(sink.data == [1, 2, 3, 4, 5, 6, 7, 8, 9]);
}

@("BufferedOutputStream rejects a bad range before writing")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new BufferedOutputStream(sink, 4);

    ubyte[] one = [1];
    assertThrown!IndexOutOfBoundsException(output.write(one, -1, 1));
    assertThrown!IndexOutOfBoundsException(output.write(one, 0, 2));
    assert(sink.data.length == 0);
}

@("BufferedOutputStream uses the 8192-byte default buffer")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new BufferedOutputStream(sink);

    ubyte[] small = new ubyte[100];
    output.write(small);
    assert(sink.data.length == 0);

    ubyte[] large = new ubyte[8192];
    output.write(large);
    assert(sink.data.length == 8292);

    output.close();
    assert(sink.closes == 1);
}

@("BufferedOutputStream flushes its buffer when the wrapped flush fails")
unittest
{
    auto sink = new RecordingOutput;
    auto output = new BufferedOutputStream(sink, 4);

    output.write(1);
    output.close();
    assert(sink.data == [1]);
    assert(sink.flushes == 1);
}
