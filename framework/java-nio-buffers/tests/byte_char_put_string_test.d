// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for heap byte-view CharBuffer string puts.
module byte_char_put_string_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("Odd-origin byte views write UTF-16 code units in captured byte order")
unittest
{
    const text = "A\u00E9\u4E2D\U0001F600Z";

    auto bigRaw = ByteBuffer.allocate(13).position(1);
    auto bigView = bigRaw.order(ByteOrder.BIG_ENDIAN).asCharBuffer();
    assert(bigView.put(text) is bigView);
    assert(bigView.position() == 6);
    assert(bigRaw.get(1) == 0x00 && bigRaw.get(2) == 0x41);
    assert(bigRaw.get(3) == 0x00 && bigRaw.get(4) == cast(byte) 0xE9);
    assert(bigView.flip().toString() == text);

    auto littleRaw = ByteBuffer.allocate(13).position(1);
    auto littleView = littleRaw.order(ByteOrder.LITTLE_ENDIAN).asCharBuffer();
    assert(littleView.put(text, 2, 4) is littleView);
    assert(littleView.position() == 2);
    assert(littleView.get(0) == 0x4E2D && littleView.get(1) == 0xD83D);
    assert(littleView.put(text, 4, 6) is littleView);
    assert(littleView.flip().toString() == "\u4E2D\U0001F600Z");
    assert(littleRaw.get(1) == 0x2D && littleRaw.get(2) == 0x4E);
}

@("Read-only byte views validate string bounds before throwing ReadOnlyBufferException")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        byte[] backing = [1, 2, 3, 4, 5, 6, 7, 8];
        auto view = ByteBuffer.wrap(backing).order(order).asReadOnlyBuffer().asCharBuffer().limit(3).position(1).mark();

        auto err = collectException!IndexOutOfBoundsException(view.put("abcd", -1, 2));
        assert(err.getMessage() == "Range [-1, -1 + 3) out of bounds for length 4");
        err = collectException!IndexOutOfBoundsException(view.put("abcd", 3, 1));
        assert(err.getMessage() == "Range [3, 3 + -2) out of bounds for length 4");
        assertThrown!ReadOnlyBufferException(view.put("abcd", 0, 4));
        assertThrown!ReadOnlyBufferException(view.put("abcd"));
        assertThrown!ReadOnlyBufferException(view.put("abcd", 4, 4));
        assertThrown!ReadOnlyBufferException(view.put(""));
        assertThrown!ReadOnlyBufferException(view.put(cast(const(char)[]) null));
        assert(backing[] == [1, 2, 3, 4, 5, 6, 7, 8]);
        assert(view.position() == 1 && view.reset().position() == 1);

        auto full = ByteBuffer.allocate(4).order(order).asReadOnlyBuffer().asCharBuffer().position(2);
        assertThrown!ReadOnlyBufferException(full.put(""));
        assertThrown!ReadOnlyBufferException(full.put("abcd", 4, 4));
    }

    auto writable = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).asCharBuffer().position(1).mark();
    assertThrown!BufferOverflowException(writable.put("ab"));
    assert(writable.position() == 1 && writable.reset().position() == 1);
}
