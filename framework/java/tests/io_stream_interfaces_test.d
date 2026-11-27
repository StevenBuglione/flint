// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the Java stream interfaces and the default InputStream contract. */
module flint.java.io_stream_interfaces_test;

import flint.java.io : Closeable, Flushable, IOException, InputStream, OutputStream, Writer;
import flint.java.lang : AutoCloseable;
import std.exception : assertThrown;

@safe:

private final class Bytes : InputStream
{
    ubyte[] data;
    size_t position;

    override int read()
    {
        return position < data.length ? data[position++] : -1;
    }
}

private final class CountingSink : OutputStream
{
    int flushes;
    int closes;
    int last;

    override void write(int value)
    {
        last = value & 0xFF;
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

@("Java streams implement the close and flush interfaces")
unittest
{
    static assert(is(InputStream : Closeable));
    static assert(is(Closeable : AutoCloseable));
    static assert(is(OutputStream : Closeable));
    static assert(is(OutputStream : Flushable));
    static assert(is(Writer : Closeable));
    static assert(is(Writer : Flushable));
}

@("InputStream defaults report no availability and no mark support")
unittest
{
    auto input = new Bytes;
    input.data = [1, 2];

    assert(input.available() == 0);
    assert(!input.markSupported());

    input.mark(4);
    assert(input.read() == 1);
}

@("InputStream reset rejects an unsupported mark with the Java detail message")
unittest
{
    auto input = new Bytes;
    input.data = [1, 2];

    IOException failure;
    try
        input.reset();
    catch (IOException caught)
        failure = caught;

    assert(failure !is null);
    assert(failure.getMessage() == "mark/reset not supported");
}

@("OutputStream dispatch through Closeable and Flushable reaches the overrides")
unittest
{
    auto sink = new CountingSink;
    OutputStream stream = sink;
    Flushable flushable = sink;
    Closeable closeable = sink;

    stream.write(0x141);
    flushable.flush();
    closeable.close();

    assert(sink.last == 0x41, "write(int) keeps the low eight bits");
    assert(sink.flushes == 1);
    assert(sink.closes == 1);
}
