// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_subsequence_test;

import flint.java.lang : UnsupportedOperationException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown;

@safe:

@("Odd-origin byte-backed subsequences preserve byte order and live storage")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        auto parent = ByteBuffer.allocate(17).position(1).mark().order(order);
        const wchar[6] input = [11, 22, 0xD800, 0xDC00, 0xFFFF, 66];
        auto view = parent.asCharBuffer().slice(1, 6).put(0, input[]).position(2).limit(5).mark();
        assert(view.length() == 3 && view.charAt(0) == 0xD800);
        auto sub = view.subSequence(1, 3);
        assert(sub.capacity() == 6 && sub.position() == 3 && sub.limit() == 5);
        assert(sub.order() == order && sub.charAt(0) == 0xDC00 && sub.charAt(1) == 0xFFFF);
        assertThrown!InvalidMarkException(sub.reset());

        sub.put(3, cast(wchar) 0xCAFE);
        assert(view.charAt(1) == 0xCAFE && parent.getChar(9) == 0xCAFE);
        auto readOnly = view.asReadOnlyBuffer().subSequence(1, 2);
        assert(readOnly.isReadOnly() && readOnly.order() == order && readOnly.charAt(0) == 0xCAFE);
        assertThrown!UnsupportedOperationException(readOnly.arrayOffset());
        assertThrown!ReadOnlyBufferException(readOnly.put(3, cast(wchar) 0));
        auto empty = view.subSequence(3, 3);
        assert(empty.capacity() == 6 && empty.isEmpty() && empty.order() == order);
        assert(view.position() == 2 && view.reset().position() == 2 && parent.reset().position() == 1);
    }
}
