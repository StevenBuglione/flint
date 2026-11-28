// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's BufferedWriter over Flint's Writer sink. */
module flint.java.io.buffered_writer_contract_test;

import flint.java.io : BufferedWriter, IOException, StringWriter, Writer;

import std.exception : assertThrown;

import flint.java.lang : IllegalArgumentException, NullPointerException, System;

@safe:

private final class CountingWriter : Writer
{
    string data;
    size_t flushes;
    size_t closes;

    override void write(scope const(char)[] text)
    {
        data ~= text;
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

@("BufferedWriter rejects a null writer and a non-positive buffer size")
unittest
{
    assertThrown!NullPointerException(new BufferedWriter(cast(Writer) null));
    assertThrown!IllegalArgumentException(new BufferedWriter(new StringWriter, 0));
    assertThrown!IllegalArgumentException(new BufferedWriter(new StringWriter, -1));
}

@("BufferedWriter holds text until it is flushed")
unittest
{
    auto sink = new CountingWriter;
    auto writer = new BufferedWriter(sink, 8);

    writer.write("abc");
    assert(sink.data == "");
    writer.flush();
    assert(sink.data == "abc");
    assert(sink.flushes == 1);
}

@("BufferedWriter passes a character array at least the buffer size straight through")
unittest
{
    auto sink = new CountingWriter;
    auto writer = new BufferedWriter(sink, 4);

    writer.write([cast(wchar) 'a', cast(wchar) 'b', cast(wchar) 'c', cast(wchar) 'd', cast(wchar) 'e']);
    assert(sink.data == "abcde");
}

@("BufferedWriter keeps a surrogate pair split across two writes")
unittest
{
    auto sink = new CountingWriter;
    auto writer = new BufferedWriter(sink, 8);

    writer.write([cast(wchar) 0xD83D]);
    writer.write([cast(wchar) 0xDE00]);
    assert(sink.data == "");
    writer.flush();
    assert(sink.data == "😀");
}

@("BufferedWriter.newLine writes the platform line separator")
unittest
{
    auto sink = new CountingWriter;
    auto writer = new BufferedWriter(sink);

    writer.write("a");
    writer.newLine();
    writer.write("b");
    writer.flush();
    assert(sink.data == "a" ~ System.lineSeparator() ~ "b");
}

@("BufferedWriter.close flushes once, closes the sink once and rejects later use")
unittest
{
    auto sink = new CountingWriter;
    auto writer = new BufferedWriter(sink, 8);

    writer.write("hi");
    writer.close();
    assert(sink.data == "hi");
    assert(sink.closes == 1);

    writer.close();
    assert(sink.closes == 1);

    assertThrown!IOException(writer.write("x"));
    assertThrown!IOException(writer.flush());
}
