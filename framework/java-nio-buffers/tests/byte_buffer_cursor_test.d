// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 heap ByteBuffer contract.
module byte_buffer_cursor_test;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private void rejectsMessage(T)(scope void delegate() @safe attempt, string expected)
{
    try
        attempt();
    catch (T exception)
    {
        assert(exception.getMessage() == expected);
        return;
    }
    assert(false, "Expected Java exception");
}

@("Heap ByteBuffer cursor invalidates marks and preserves fluent identity")
unittest
{
    auto bytes = ByteBuffer.allocate(4);
    Buffer cursor = bytes;
    assert(cursor.capacity() == 4 && cursor.limit() == 4 && cursor.remaining() == 4);
    assert(bytes.position(2).mark().position(3).reset() is bytes);
    assert(cursor.position() == 2 && cursor.hasRemaining());

    assert(cursor.limit(1) is cursor);
    assert(bytes.position() == 1 && bytes.remaining() == 0);
    assertThrown!InvalidMarkException(bytes.reset());

    bytes.clear().position(3).mark().flip();
    assert(bytes.position() == 0 && bytes.limit() == 3);
    assertThrown!InvalidMarkException(bytes.reset());
    bytes.position(2).mark().rewind();
    assert(bytes.position() == 0 && bytes.limit() == 3);
    assertThrown!InvalidMarkException(bytes.reset());

    rejectsMessage!IllegalArgumentException(() { bytes.position(-1); }, "newPosition < 0: (-1 < 0)");
    rejectsMessage!IllegalArgumentException(() { bytes.position(4); }, "newPosition > limit: (4 > 3)");
    rejectsMessage!IllegalArgumentException(() { bytes.limit(-1); }, "newLimit < 0: (-1 < 0)");
    rejectsMessage!IllegalArgumentException(() { bytes.limit(5); }, "newLimit > capacity: (5 > 4)");
    assert(bytes.position() == 0 && bytes.limit() == 3);
}

@("Heap ByteBuffer views share bytes and carry independent cursors")
unittest
{
    byte[] storage = [1, 2, 3, 4];
    auto bytes = ByteBuffer.wrap(storage, 1, 2);
    assert(bytes.capacity() == 4 && bytes.position() == 1 && bytes.limit() == 3);
    assert(bytes.hasArray() && !bytes.isDirect() && bytes.arrayOffset() == 0);
    assert(bytes.array().ptr == storage.ptr);
    Buffer erased = bytes;
    assert(erased.array().get!(byte[])().ptr == storage.ptr);

    bytes.order(ByteOrder.LITTLE_ENDIAN);
    auto slice = bytes.slice();
    auto duplicate = bytes.mark().duplicate();
    auto readOnly = bytes.asReadOnlyBuffer();
    assert(slice.capacity() == 2 && slice.position() == 0 && slice.arrayOffset() == 1);
    assert(slice.order() == ByteOrder.BIG_ENDIAN && duplicate.order() == ByteOrder.BIG_ENDIAN);
    assert(readOnly.order() == ByteOrder.BIG_ENDIAN && readOnly.isReadOnly() && !readOnly.hasArray());
    assert(slice.put(cast(byte) 7) is slice);
    assert(storage[1] == 7 && bytes.position() == 1 && readOnly.get(1) == 7);
    assert(duplicate.position(2).reset().position() == 1);
    assertThrown!ReadOnlyBufferException(readOnly.put(cast(byte) 1));
    assertThrown!ReadOnlyBufferException(readOnly.array());
    assertThrown!ReadOnlyBufferException(readOnly.arrayOffset());
    assertThrown!ReadOnlyBufferException((cast(Buffer) readOnly).array());

    auto indexed = bytes.slice(0, 2);
    indexed.put(1, cast(byte) 8);
    assert(indexed.position() == 0 && storage[1] == 8 && bytes.position() == 1);
    rejectsMessage!IndexOutOfBoundsException(() { bytes.slice(2, 2); }, "Range [2, 2 + 2) out of bounds for length 3");
}

@("Heap ByteBuffer scalar access uses the limit and preserves the cursor on failure")
unittest
{
    auto bytes = ByteBuffer.allocate(1);
    assert(bytes.order() == ByteOrder.BIG_ENDIAN);
    assert(bytes.order(Nullable!ByteOrder.init) is bytes);
    assert(bytes.order() == ByteOrder.LITTLE_ENDIAN);
    assert(bytes.put(cast(byte)-2) is bytes);
    assertThrown!BufferOverflowException(bytes.put(cast(byte) 10));
    assert(bytes.position() == 1 && bytes.get(0) == -2);
    rejectsMessage!IndexOutOfBoundsException(() { bytes.get(1); }, "Index 1 out of bounds for length 1");
    assert(bytes.flip().get() == -2);
    assertThrown!BufferUnderflowException(bytes.get());
    assert(bytes.position() == 1);

    auto empty = ByteBuffer.wrap(null);
    assert(empty.capacity() == 0 && empty.array().length == 0);
    assert(!(cast(Buffer) empty).array().isNull());
}

@("Heap ByteBuffer value operations compare remaining signed bytes")
unittest
{
    byte[] leftData = [9, -128, 1];
    byte[] equalData = [-128, 1];
    byte[] rightData = [127, 1];
    auto left = ByteBuffer.wrap(leftData).position(1);
    auto equal = ByteBuffer.wrap(equalData);
    auto right = ByteBuffer.wrap(rightData);
    assert(left.equals(equal) && left.hashCode() == equal.hashCode());
    assert(left.compareTo(right) < 0 && left.mismatch(right) == 0);
    assert(left.mismatch(equal) == -1);
    byte[] prefix = [-128];
    assert(left.mismatch(ByteBuffer.wrap(prefix)) == 1);
    assert(!left.equals(null));
    assertThrown!NullPointerException(left.compareTo(null));
    assertThrown!NullPointerException(left.mismatch(null));
}

@("Heap ByteBuffer bulk reads copy aliased storage through a read-only slice")
unittest
{
    byte[] storage = [0, 1, 2, 3, 4, 5];
    auto view = ByteBuffer.wrap(storage, 1, 4).slice().asReadOnlyBuffer();
    view.position(1).mark();
    assert(view.get(storage, 3, 3) is view);
    assert(storage == [0, 1, 2, 2, 3, 4]);
    assert(view.position() == 4 && view.reset().position() == 1);

    assert(view.get(1, storage, 0, 3) is view);
    assert(storage == [2, 2, 3, 2, 3, 4]);
    assert(view.position() == 1);
    byte[1] one = [-1];
    assert(view.get(0, one[]) is view && one[0] == 2);
    assert(view.position() == 1);
    assert(view.get(one[]) is view && one[0] == 3 && view.position() == 2);
    assert(view.get(4, null) is view && view.position() == 2);
}

@("Heap ByteBuffer bulk read failures preserve the target, position, and mark")
unittest
{
    auto view = ByteBuffer.allocate(4).limit(3).position(2).mark();
    byte[2] guard = [9, 9];
    rejectsMessage!IndexOutOfBoundsException(() { view.get(guard[], 1, 2); },
            "Range [1, 1 + 2) out of bounds for length 2");
    assertThrown!BufferUnderflowException(view.get(guard[]));
    rejectsMessage!IndexOutOfBoundsException(() { view.get(2, guard[], 1, 2); },
            "Range [2, 2 + 2) out of bounds for length 3");
    rejectsMessage!IndexOutOfBoundsException(() { view.get(0, guard[], 1, 2); },
            "Range [1, 1 + 2) out of bounds for length 2");
    assert(view.position() == 2 && view.reset().position() == 2);
    assert(guard[] == [9, 9]);
    assert(view.get(null) is view && view.position() == 2);
}
