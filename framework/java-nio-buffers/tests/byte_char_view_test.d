// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_view_test;

import flint.java.lang : UnsupportedOperationException;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown;

@safe:

@("Heap ByteBuffer character views share an odd byte origin and capture order")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        byte[] storage = [99, 99, 99, 0x12, 0x34, 0x56, 0x78, 0x7F, 99];
        auto parent = ByteBuffer.wrap(storage, 2, 6).slice().order(order).position(1).mark();
        auto view = parent.asCharBuffer();
        assert(parent.position() == 1 && parent.limit() == 6 && parent.reset().position() == 1);
        assert(view.position() == 0 && view.limit() == 2 && view.capacity() == 2);
        assert(view.order() == order && !view.isDirect());
        assertThrown!InvalidMarkException(view.reset());

        const initial = order == ByteOrder.BIG_ENDIAN ? 0x1234 : 0x3412;
        assert(view.mark().get() == initial && parent.position() == 1);
        parent.putChar(3, cast(wchar) 0xDC00);
        assert(view.get(1) == 0xDC00 && view.position() == 1);
        assert(view.put(cast(wchar) 0xD800) is view && view.position() == 2);
        assert(parent.position() == 1 && parent.getChar(3) == 0xD800);
        assert(view.duplicate().reset().position() == 0 && view.position() == 2);

        parent.order(order == ByteOrder.BIG_ENDIAN ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN);
        assert(view.order() == order && view.get(1) == 0xD800);
        auto slice = view.slice(1, 1);
        assert(slice.order() == order && slice.get(0) == 0xD800);
        slice.put(0, cast(wchar) 0xFFFF);
        assert(parent.getChar(3) == 0xFFFF && view.get(1) == 0xFFFF);
        assert(view.position(1).slice().get() == 0xFFFF);
        assert(storage[2] == 99 && storage[7] == 0x7F && storage[8] == 99);
    }
}

@("Byte-backed character views reject array access with or without read-only state")
unittest
{
    auto parent = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN);
    parent.putChar(0, cast(wchar) 0xD800);
    auto writable = parent.asCharBuffer();
    assert(!writable.hasArray() && !writable.isReadOnly());
    assertThrown!UnsupportedOperationException(writable.array());
    assertThrown!UnsupportedOperationException(writable.arrayOffset());
    assertThrown!UnsupportedOperationException((cast(Buffer) writable).array());

    auto readOnly = parent.asReadOnlyBuffer().order(ByteOrder.LITTLE_ENDIAN).asCharBuffer();
    assert(readOnly.isReadOnly() && !readOnly.hasArray());
    assert(readOnly.order() == ByteOrder.LITTLE_ENDIAN && readOnly.get(0) == 0xD800);
    assert(writable.asReadOnlyBuffer().order() == ByteOrder.LITTLE_ENDIAN);
    assertThrown!UnsupportedOperationException(readOnly.array());
    assertThrown!UnsupportedOperationException(readOnly.arrayOffset());
    assertThrown!ReadOnlyBufferException(readOnly.put(-1, cast(wchar) 1));

    auto empty = ByteBuffer.allocate(1).asCharBuffer();
    assert(empty.capacity() == 0 && empty.limit() == 0 && !empty.hasArray());
    assertThrown!UnsupportedOperationException(empty.array());
    assertThrown!BufferUnderflowException(empty.get());
}
