// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module char_buffer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown;

@safe:

private void rejects(T)(scope void delegate() @safe attempt, string message)
{
    try
        attempt();
    catch (T exception)
    {
        assert(message is null ? exception.getMessage() is null : exception.getMessage() == message);
        return;
    }
    assert(false, "Expected Java exception");
}

@("Heap CharBuffer exposes live UTF-16 backing and independent cursors")
unittest
{
    auto allocated = CharBuffer.allocate(2);
    assert(allocated.get(0) == 0 && allocated.get(1) == 0);
    assert(allocated.array().length == 2 && allocated.order() == ByteOrder.nativeOrder());
    rejects!IllegalArgumentException(() { CharBuffer.allocate(-1); }, "capacity < 0: (-1 < 0)");

    wchar[] values = [9, 0xD800, 0xFFFF, 3, 7];
    auto root = CharBuffer.wrap(values, 1, 3).mark();
    assert(root.array().ptr == values.ptr && root.arrayOffset() == 0);
    assert(root.capacity() == 5 && root.limit() == 4 && root.position() == 1);
    assert(root.hasArray() && !root.isReadOnly() && !root.isDirect());
    Buffer erased = root;
    assert(erased.array().get!(wchar[])().ptr == values.ptr);

    auto view = root.slice();
    assert(view.array().ptr == values.ptr && view.arrayOffset() == 1);
    assert(view.capacity() == 3 && view.limit() == 3 && view.position() == 0);
    assert(view.mark().get() == 0xD800);
    assert(view.put(1, cast(wchar) 0xDC00) is view && values[2] == 0xDC00);
    assert(view.get(1) == 0xDC00 && view.position() == 1);
    assert(view.put(cast(wchar) 0xFFFF) is view && values[2] == 0xFFFF);
    assert(view.position() == 2 && root.position() == 1);
    auto duplicate = view.duplicate();
    assert(duplicate.reset().position() == 0 && view.position() == 2);
    auto indexed = root.slice(2, 1);
    assert(indexed.arrayOffset() == 2 && indexed.get() == 0xFFFF);

}

@("Heap CharBuffer read-only views reject backing access and writes")
unittest
{
    wchar[] values = [9, 0xD800, 0xFFFF, 3];
    auto view = CharBuffer.wrap(values, 1, 3).slice();
    auto readOnly = view.asReadOnlyBuffer();
    assert(!readOnly.hasArray() && readOnly.isReadOnly() && !readOnly.isDirect());
    assert(readOnly.order() == ByteOrder.nativeOrder() && readOnly.get(1) == 0xFFFF);
    assertThrown!ReadOnlyBufferException(readOnly.array());
    assertThrown!ReadOnlyBufferException(readOnly.arrayOffset());
    assertThrown!ReadOnlyBufferException((cast(Buffer) readOnly).array());
    assertThrown!ReadOnlyBufferException(readOnly.put(-1, cast(wchar) 8));
}

@("Heap CharBuffer failures preserve positions and no-detail index diagnostics")
unittest
{
    wchar[] values = [9, 1, 2, 3, 7];
    auto root = CharBuffer.wrap(values, 1, 3);
    auto view = root.slice();
    rejects!IndexOutOfBoundsException(() { view.get(3); }, null);
    rejects!IndexOutOfBoundsException(() { view.put(-1, cast(wchar) 8); }, null);
    rejects!IndexOutOfBoundsException(() { root.slice(3, 2); }, "Range [3, 3 + 2) out of bounds for length 4");
    rejects!IndexOutOfBoundsException(() { CharBuffer.wrap(values, 3, 4); }, null);

    view.position(3).mark();
    assertThrown!BufferUnderflowException(view.get());
    assertThrown!BufferOverflowException(view.put(cast(wchar) 8));
    assert(view.reset().position() == 3);
    assert(view.flip().position() == 0 && view.limit() == 3);
    assertThrown!InvalidMarkException(view.reset());
    assert(view.clear().position() == 0 && view.limit() == 3);
    assert(view.position(2).rewind().position() == 0);
    assert(values == [9, 1, 2, 3, 7]);

    // Java needs the same cast: wrap(null) is ambiguous between char[] and CharSequence there too.
    auto empty = CharBuffer.wrap(cast(wchar[]) null);
    assert(empty.capacity() == 0 && empty.hasArray() && empty.array().length == 0);
    assert(!(cast(Buffer) empty).array().isNull());
}
