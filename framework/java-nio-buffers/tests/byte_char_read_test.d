// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_read_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("Character read delegates to byte-backed put on partially overlapping windows")
unittest
{
    foreach (left; [false, true])
    {
        auto parent = ByteBuffer.allocate(15).position(1).mark();
        auto from = parent.duplicate().position(left ? 2 : 1).order(ByteOrder.BIG_ENDIAN).asCharBuffer();
        auto into = parent.duplicate().position(left ? 1 : 2).order(ByteOrder.LITTLE_ENDIAN).asCharBuffer();
        const wchar[4] data = [0x1234, 0xD800, 0xFFFF, 0xDC00];
        from.put(data[]).flip().mark();
        into.limit(3).mark();

        auto sourceReadOnly = from.asReadOnlyBuffer();
        auto self = collectException!IllegalArgumentException(sourceReadOnly.read(sourceReadOnly));
        assert(self.getMessage() == "The source buffer is this buffer");
        auto targetReadOnly = into.asReadOnlyBuffer();
        assertThrown!ReadOnlyBufferException(from.read(targetReadOnly));
        assert(from.position() == 0 && from.limit() == 4 && from.reset().position() == 0);
        assert(targetReadOnly.position() == 0 && targetReadOnly.reset().position() == 0);

        assert(from.read(into) == 3);
        assert(from.position() == 3 && from.limit() == 4 && into.position() == 3 && into.limit() == 3);
        wchar[3] output;
        into.get(0, output[]);
        assert(output[] == data[0 .. 3]);
        assert(from.reset().position() == 0 && into.reset().position() == 0 && parent.reset().position() == 1);
    }
}
