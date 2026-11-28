// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's pushback input stream. */
module flint.java.io.pushback_stream_contract_test;

import flint.java.io : ByteArrayInputStream, IOException, OutputStream, PushbackInputStream;
import flint.java.lang : IndexOutOfBoundsException;
import std.exception : assertThrown;

@safe:

private PushbackInputStream over(const(ubyte)[] bytes, int size = 1)
{
    return new PushbackInputStream(new ByteArrayInputStream(bytes), size);
}

private final class RecordingOutput : OutputStream
{
    ubyte[] data;

    override void write(int value)
    {
        data ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] buffer, int offset, int length)
    {
        data ~= buffer[offset .. offset + length];
    }
}

@("PushbackInputStream reads pushed-back bytes before the wrapped stream")
unittest
{
    auto input = over([1, 2]);
    assert(input.read() == 1);

    input.unread(9);
    assert(input.read() == 9);
    assert(input.read() == 2);
    assert(input.read() == -1);
}

@("PushbackInputStream ranged reads take the pushed-back bytes first")
unittest
{
    auto input = over([1, 2, 3], 2);
    input.unread(9);
    input.unread(8);

    ubyte[] buffer = new ubyte[4];
    assert(input.read(buffer) == 4);
    assert(buffer == [ubyte(8), ubyte(9), ubyte(1), ubyte(2)]);

    assert(input.read(buffer[0 .. 1]) == 1);
    assert(buffer[0] == 3);
    assert(input.read(buffer[0 .. 1]) == -1);
}

@("PushbackInputStream reports a full pushback buffer")
unittest
{
    auto input = over([1]);
    input.unread(2);
    assertThrown!IOException(input.unread(3));

    auto two = over([1], 2);
    two.unread(4);
    two.unread(5);
    ubyte[] three = [6, 7, 8];
    assertThrown!IOException(two.unread(three));
}

@("PushbackInputStream unread validates the range")
unittest
{
    auto input = over([1], 2);
    ubyte[] one = [1];
    assertThrown!IndexOutOfBoundsException(input.unread(one, -1, 1));
    assertThrown!IndexOutOfBoundsException(input.unread(one, 0, 2));
}

@("PushbackInputStream available and skip include the pushed-back bytes")
unittest
{
    auto input = over([1, 2, 3, 4]);
    input.unread(9);
    assert(input.available() == 5);
    assert(input.skip(1) == 1);
    assert(input.read() == 1);
    assert(input.skip(2) == 2);
    assert(input.read() == 4);
    assert(input.read() == -1);
}

@("PushbackInputStream transferTo copies the pushed-back and wrapped bytes")
unittest
{
    auto input = over([1, 2, 3]);
    input.unread(9);
    auto sink = new RecordingOutput;
    assert(input.transferTo(sink) == 4);
    assert(sink.data == [ubyte(9), ubyte(1), ubyte(2), ubyte(3)]);
    assert(input.read() == -1);
}

@("PushbackInputStream does not support marks")
unittest
{
    auto input = over([1]);
    assert(!input.markSupported());
    input.mark(5);
    assertThrown!IOException(input.reset());
}

@("PushbackInputStream reports a closed stream after close and closes once")
unittest
{
    auto source = new ByteArrayInputStream([1, 2]);
    auto input = new PushbackInputStream(source);
    assert(input.read() == 1);

    input.close();
    input.close();
    assertThrown!IOException(input.read());
    assertThrown!IOException(input.unread(1));
    assertThrown!IOException(input.available());
    assertThrown!IOException(input.skip(1));
    assertThrown!IOException(input.reset());
}
