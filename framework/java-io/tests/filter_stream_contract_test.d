// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's filter stream bases. */
module flint.java.io.filter_stream_contract_test;

import flint.java.io : FilterInputStream, FilterOutputStream, IOException, InputStream, OutputStream;
import flint.java.lang : IndexOutOfBoundsException;
import std.exception : assertThrown, collectException;

@safe:

private final class RecordingInput : InputStream
{
    ubyte[] data;
    size_t position;
    int availableValue;
    long skipValue;
    int rangedCalls;
    bool closed;
    bool marked;
    bool markSupportedValue = true;
    int markLimit = -1;
    size_t markPosition;

    override int read()
    {
        return position < data.length ? data[position++] : -1;
    }

    override int read(scope ubyte[] buffer, int offset, int length)
    {
        ++rangedCalls;
        return super.read(buffer, offset, length);
    }

    override long skip(long count)
    {
        assert(count == 11);
        return skipValue;
    }

    override int available()
    {
        return availableValue;
    }

    override void close()
    {
        closed = true;
    }

    override void mark(int readLimit)
    {
        marked = true;
        markLimit = readLimit;
        markPosition = position;
    }

    override void reset()
    {
        position = markPosition;
    }

    override bool markSupported()
    {
        return markSupportedValue;
    }
}

private final class ExposedInputFilter : FilterInputStream
{
    this(InputStream input)
    {
        super(input);
    }

    InputStream wrapped()
    {
        return in_;
    }
}

private final class RecordingOutput : OutputStream
{
    int[] written;
    int flushes;
    int closes;
    string flushFailure;
    string closeFailure;

    override void write(int value)
    {
        written ~= value & 0xFF;
    }

    override void flush()
    {
        ++flushes;
        if (flushFailure !is null)
            throw new IOException(flushFailure);
    }

    override void close()
    {
        ++closes;
        if (closeFailure !is null)
            throw new IOException(closeFailure);
    }
}

private final class CountingOutputFilter : FilterOutputStream
{
    int perByte;

    this(OutputStream output)
    {
        super(output);
    }

    alias write = FilterOutputStream.write;

    override void write(int value)
    {
        ++perByte;
        super.write(value);
    }

    OutputStream wrapped()
    {
        return out_;
    }
}

@("FilterInputStream delegates every InputStream operation to the wrapped stream")
unittest
{
    auto source = new RecordingInput;
    source.data = [1, 2, 3, 4];
    source.availableValue = 7;
    source.skipValue = 5;
    auto filter = new ExposedInputFilter(source);

    assert(filter.wrapped() is source);
    assert(filter.read() == 1);
    assert(filter.read() == 2);
    assert(source.markSupported());
    filter.mark(3);
    assert(source.marked && source.markLimit == 3);
    assert(filter.read() == 3);
    filter.reset();
    assert(filter.read() == 3);

    ubyte[] buffer = new ubyte[4];
    const count = filter.read(buffer);
    assert(count == 1);
    assert(buffer[0] == 4);
    assert(source.rangedCalls == 1);

    assert(filter.available() == 7);
    assert(filter.skip(11) == 5);
    assert(filter.markSupported());
    filter.close();
    assert(source.closed);
}

@("FilterOutputStream delegates writes and flushes to the wrapped stream")
unittest
{
    auto sink = new RecordingOutput;
    auto filter = new CountingOutputFilter(sink);

    assert(filter.wrapped() is sink);
    filter.write(0x141);
    assert(sink.written == [0x41]);
    assert(filter.perByte == 1);

    ubyte[] three = [1, 2, 3];
    filter.write(three);
    assert(sink.written == [0x41, 1, 2, 3]);
    assert(filter.perByte == 4);

    ubyte[] padded = [9, 4, 5, 9];
    filter.write(padded, 1, 2);
    assert(sink.written == [0x41, 1, 2, 3, 4, 5]);
    assert(filter.perByte == 6);

    ubyte[] one = [1];
    assertThrown!IndexOutOfBoundsException(filter.write(one, -1, 1));
    assertThrown!IndexOutOfBoundsException(filter.write(one, 0, 2));
    assert(sink.written.length == 6);

    filter.flush();
    assert(sink.flushes == 1);
}

@("FilterOutputStream closes once after flushing, like Java")
unittest
{
    auto sink = new RecordingOutput;
    auto filter = new FilterOutputStream(sink);

    filter.close();
    assert(sink.flushes == 1);
    assert(sink.closes == 1);

    filter.close();
    assert(sink.flushes == 1);
    assert(sink.closes == 1);
}

@("FilterOutputStream closes the wrapped stream when its flush fails")
unittest
{
    auto sink = new RecordingOutput;
    sink.flushFailure = "flush failed";
    sink.closeFailure = "close failed";
    auto filter = new FilterOutputStream(sink);

    auto failure = collectException!IOException(filter.close());
    assert(failure !is null);
    assert(failure.getMessage() == "flush failed");
    assert(sink.closes == 1);

    filter.close();
    assert(sink.flushes == 1);
    assert(sink.closes == 1);
}

@("FilterOutputStream reports a close failure")
unittest
{
    auto sink = new RecordingOutput;
    sink.closeFailure = "close failed";
    auto filter = new FilterOutputStream(sink);

    auto failure = collectException!IOException(filter.close());
    assert(failure !is null);
    assert(failure.getMessage() == "close failed");
    assert(sink.flushes == 1);
    assert(sink.closes == 1);

    filter.close();
    assert(sink.closes == 1);
}
