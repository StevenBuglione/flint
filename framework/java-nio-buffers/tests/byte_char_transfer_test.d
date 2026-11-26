// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_transfer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("Character buffer transfers swap overlapping grow and shrink directions")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        auto parent = ByteBuffer.allocate(15).position(1).mark();
        const reversed = order == ByteOrder.BIG_ENDIAN ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN;
        const wchar[4] original = [0x1234, 0xD800, 0xDC00, 0xFFFF];
        foreach (left; [false, true])
        {
            auto from = parent.duplicate().position(left ? 2 : 1).order(order).asCharBuffer();
            auto into = parent.duplicate().position(left ? 1 : 2).order(reversed).asCharBuffer();
            from.put(original[]).flip().mark();
            assert(into.mark().put(from) is into);
            wchar[4] output;
            assert(into.get(0, output[]) is into && output[] == original[]);
            assert(into.position() == 4 && from.position() == 4);
            assert(into.reset().position() == 0 && from.reset().position() == 0);
        }

        auto words = CharBuffer.allocate(5).position(1).mark();
        auto bytes = parent.order(order).asCharBuffer().position(2).mark();
        bytes.put(0, CharBuffer.wrap(original[].dup).asReadOnlyBuffer(), 0, 4);
        assert(words.put(1, bytes.asReadOnlyBuffer(), 0, 4) is words);
        assert(words.array()[1 .. $] == original[]);
        assert(words.reset().position() == 1 && bytes.reset().position() == 2 && parent.reset().position() == 1);
    }
}

@("Read-only byte-backed character transfer validates self and ranges in Java order")
unittest
{
    auto bytes = ByteBuffer.allocate(12).position(1).asCharBuffer().position(1).mark();
    auto readOnly = bytes.asReadOnlyBuffer();
    auto from = CharBuffer.allocate(6).limit(5).mark();
    auto absent = cast(CharBuffer) null;
    auto self = collectException!IllegalArgumentException(readOnly.put(readOnly));
    assert(self.getMessage() == "The source buffer is this buffer");
    assertThrown!ReadOnlyBufferException(readOnly.put(absent));
    auto range = collectException!IndexOutOfBoundsException(readOnly.put(-1, absent, 0, 0));
    assert(range.getMessage() == "Range [-1, -1 + 0) out of bounds for length 5");
    assertThrown!NullPointerException(readOnly.put(0, absent, 0, 0));
    range = collectException!IndexOutOfBoundsException(readOnly.put(0, from, 5, 1));
    assert(range.getMessage() == "Range [5, 5 + 1) out of bounds for length 5");
    assertThrown!ReadOnlyBufferException(readOnly.put(0, from, 5, 0));
    assertThrown!ReadOnlyBufferException(readOnly.compact());
    assert(readOnly.reset().position() == 1 && from.reset().position() == 0);
}

@("Byte-backed character compact works through a nonzero odd slice origin")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        auto parent = ByteBuffer.allocate(15).put(0, 99).put(14, 98).position(1).limit(14).mark().order(order);
        auto slice = parent.asCharBuffer().slice(1, 5);
        const wchar[5] input = [1, 2, 3, 4, 5];
        slice.put(input[]).limit(4).position(1).mark();
        assert(slice.compact() is slice && slice.order() == order);
        assert(slice.position() == 3 && slice.limit() == 5);
        assert(parent.getChar(3) == 2 && parent.getChar(5) == 3 && parent.getChar(7) == 4);
        assert(parent.reset().position() == 1 && parent.get(0) == 99 && parent.array()[14] == 98);
        assertThrown!InvalidMarkException(slice.reset());
        assert(slice.position(5).mark().compact() is slice);
        assert(slice.position() == 0 && slice.limit() == 5 && slice.get(0) == 2);
        assertThrown!InvalidMarkException(slice.reset());
    }
}
