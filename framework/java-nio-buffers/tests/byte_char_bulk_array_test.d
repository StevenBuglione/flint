// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_char_bulk_array_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown;

@safe:

@("Bulk character arrays cross unaligned heap byte views in either order")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        wchar[4] values = [0x0123, 0xD800, 0xDC00, 0xFFFF];
        wchar[4] output;
        byte[] storage = [99, 0, 0, 0, 0, 0, 0, 0, 0, 98];
        auto parent = ByteBuffer.wrap(storage).position(1).mark().order(order);
        auto view = parent.asCharBuffer().position(1).mark().limit(3);
        assert(view.put(values[], 1, 2) is view && view.position() == 3);
        assert(parent.getChar(3) == values[1] && parent.getChar(5) == values[2]);
        assert(view.put(0, values[0 .. 1]) is view && view.position() == 3);
        assert(view.get(1, output[], 1, 2) is view && view.position() == 3);
        assert(output[1 .. 3] == values[1 .. 3]);
        assert(view.get(0, output[0 .. 1]) is view && output[0] == values[0]);
        auto readOnly = view.asReadOnlyBuffer().reset();
        assert(readOnly.get(output[1 .. 3]) is readOnly && output[1 .. 3] == values[1 .. 3]);
        assertThrown!ReadOnlyBufferException(readOnly.put(-1, values[], -1, 5));
        assertThrown!ReadOnlyBufferException(readOnly.put(values[], -1, 5));
        assertThrown!IndexOutOfBoundsException(readOnly.get(output[], -1, 5));
        assertThrown!BufferUnderflowException(readOnly.get(output[0 .. 1]));
        assert(readOnly.position() == 3 && readOnly.reset().position() == 1);
        assert(view.reset().position() == 1 && parent.reset().position() == 1);
        assert(storage[0] == 99 && storage[9] == 98);
    }
}

@("Native word slices and byte views can overlap at an odd byte offset")
unittest
{
    foreach (order; [ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN])
    {
        wchar[3] values = [0x0123, 0xD800, 0xFFFF];
        foreach (arrayIndex; [0, 1])
        {
            auto words = new wchar[5];
            auto view = ByteBuffer.wrap(cast(byte[]) words).position(1).order(order).asCharBuffer();
            auto overlapping = words[arrayIndex .. arrayIndex + values.length];
            overlapping[] = values[];
            view.put(0, overlapping);
            foreach (i, value; values)
                assert(view.get(cast(int) i) == value);

            view.position(0).mark();
            assert(view.get(overlapping) is view);
            assert(overlapping == values[] && view.position() == 3 && view.reset().position() == 0);
        }
    }
}
