// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_text_test;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;

@safe:

@("Unaligned ByteBuffer character views render the same UTF-8 in either order")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        auto parent = ByteBuffer.allocate(21).position(1).mark().order(order);
        const wchar[7] words = [0x20AC, 0xD83D, 0xDE42, 0xD800, 0xDC00, 0xDC00, 'z'];
        auto view = parent.asCharBuffer().slice(1, 8).put(1, words[]).position(1).limit(8).mark();
        assert(view.asReadOnlyBuffer().toString() == "\u20AC\U0001F642\U00010000\uFFFDz");
        assert(view.subSequence(2, 4).toString() == "\uFFFD\uFFFD");
        assert(view.position() == 1 && view.limit() == 8 && view.reset().position() == 1);
        assert(view.order() == order && parent.reset().position() == 1);
    }
}
