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
        assert(expected is null ? exception.getMessage() is null : exception.getMessage() == expected);
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
    rejectsMessage!IndexOutOfBoundsException(() { bytes.get(1); }, null);
    rejectsMessage!IndexOutOfBoundsException(() { bytes.put(-1, cast(byte) 4); }, null);
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

@("Heap ByteBuffer bulk writes copy aliased storage and preserve cursor semantics")
unittest
{
    byte[] storage = [0, 1, 2, 3, 4, 5, 6];
    auto slice = ByteBuffer.wrap(storage, 1, 5).slice().position(2).mark();
    assert(slice.put(storage, 2, 3) is slice);
    assert(storage == [0, 1, 2, 2, 3, 4, 6]);
    assert(slice.position() == 5 && slice.reset().position() == 2);

    assert(slice.put(0, storage, 2, 3) is slice);
    assert(storage == [0, 2, 2, 3, 3, 4, 6]);
    assert(slice.position() == 2);
    const byte[1] absolute = [8];
    const byte[1] relative = [9];
    assert(slice.put(3, absolute[]) is slice && storage[4] == 8);
    assert(slice.position() == 2);
    assert(slice.put(relative[]) is slice && storage[3] == 9);
    assert(slice.position() == 3);
    assert(slice.put(5, null) is slice && slice.position() == 3);
    assert(slice.put(cast(const(byte)[]) null) is slice && slice.position() == 3);
}

@("Heap ByteBuffer bulk write failures preserve both views and backing bytes")
unittest
{
    byte[] storage = [0, 1, 2, 3, 4];
    auto slice = ByteBuffer.wrap(storage).limit(4).position(3).mark();
    const byte[2] input = [7, 7];
    rejectsMessage!IndexOutOfBoundsException(() { slice.put(input[], 1, 2); },
            "Range [1, 1 + 2) out of bounds for length 2");
    assertThrown!BufferOverflowException(slice.put(input[]));
    rejectsMessage!IndexOutOfBoundsException(() { slice.put(3, input[], 1, 2); },
            "Range [3, 3 + 2) out of bounds for length 4");
    rejectsMessage!IndexOutOfBoundsException(() { slice.put(0, input[], 1, 2); },
            "Range [1, 1 + 2) out of bounds for length 2");

    auto readOnly = slice.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.put(input[], 1, 2));
    assertThrown!ReadOnlyBufferException(readOnly.put(99, input[], 1, 2));
    assertThrown!ReadOnlyBufferException(readOnly.put(cast(const(byte)[]) null));
    assertThrown!ReadOnlyBufferException(readOnly.put(4, null));
    assert(slice.position() == 3 && slice.reset().position() == 3);
    assert(readOnly.position() == 3 && readOnly.reset().position() == 3);
    assert(storage == [0, 1, 2, 3, 4]);
}

@("Heap ByteBuffer transfers overlap and validate before changing either cursor")
unittest
{
    byte[] storage = [0, 1, 2, 3, 4, 5, 6, 7];
    auto destination = ByteBuffer.wrap(storage, 1, 6).slice().position(2).mark().limit(5);
    auto source = ByteBuffer.wrap(storage, 1, 3).slice().asReadOnlyBuffer().mark();
    assert(destination.put(source) is destination);
    assert(storage == [0, 1, 2, 1, 2, 3, 6, 7]);
    assert(destination.position() == 5 && source.position() == 3);
    assert(destination.reset().position() == 2 && source.reset().position() == 0);
    assert(destination.put(0, destination, 2, 3) is destination);
    assert(storage == [0, 1, 2, 3, 2, 3, 6, 7]);
    assert(destination.position() == 2 && source.position() == 0);

    auto tooLarge = ByteBuffer.allocate(4).mark();
    rejectsMessage!IllegalArgumentException(() { destination.put(destination); }, "The source buffer is this buffer");
    assertThrown!NullPointerException(destination.put(cast(ByteBuffer) null));
    assertThrown!BufferOverflowException(destination.put(tooLarge));
    assert(tooLarge.position() == 0 && tooLarge.reset().position() == 0);
    rejectsMessage!IndexOutOfBoundsException(() { destination.put(4, cast(ByteBuffer) null, 0, 2); },
            "Range [4, 4 + 2) out of bounds for length 5");
    assertThrown!NullPointerException(destination.put(0, cast(ByteBuffer) null, 0, 2));
    rejectsMessage!IndexOutOfBoundsException(() { destination.put(0, source, 2, 2); },
            "Range [2, 2 + 2) out of bounds for length 3");
    assertThrown!ReadOnlyBufferException(source.put(source));
    assertThrown!ReadOnlyBufferException(source.put(cast(ByteBuffer) null));
    assertThrown!ReadOnlyBufferException(source.put(99, cast(ByteBuffer) null, 99, 3));
    assertThrown!ReadOnlyBufferException(source.put(99, destination, 0, 1));
    assertThrown!ReadOnlyBufferException(source.put(0, cast(ByteBuffer) null, 0, 1));
    assertThrown!ReadOnlyBufferException(source.compact());
    assert(destination.position() == 2 && destination.reset().position() == 2);
    assert(source.position() == 0 && source.reset().position() == 0);
    assert(storage == [0, 1, 2, 3, 2, 3, 6, 7]);
}

@("Heap ByteBuffer compact moves remaining bytes and clears the mark")
unittest
{
    byte[] storage = [0, 1, 2, 3, 4, 5, 6, 7];
    auto slice = ByteBuffer.wrap(storage, 1, 6).slice().order(ByteOrder.LITTLE_ENDIAN);
    slice.position(2).limit(5).mark();
    auto duplicate = slice.duplicate();
    assert(slice.compact() is slice);
    assert(storage == [0, 3, 4, 5, 4, 5, 6, 7]);
    assert(slice.position() == 3 && slice.limit() == 6 && slice.order() == ByteOrder.LITTLE_ENDIAN);
    assert(duplicate.position() == 2 && duplicate.limit() == 5 && duplicate.get(0) == 3);
    assertThrown!InvalidMarkException(slice.reset());

    slice.position(6).mark();
    assert(slice.compact().position() == 0 && slice.limit() == 6);
    assertThrown!InvalidMarkException(slice.reset());
}

@("Heap ByteBuffer short access follows view byte order and keeps marks")
unittest
{
    byte[] storage = [85, -128, 1, 0, 0, 0, 85];
    auto view = ByteBuffer.wrap(storage, 1, 5).slice().mark();
    assert(view.getShort() == -32_767);
    assert(view.position() == 2 && view.reset().position() == 0);
    view.order(ByteOrder.LITTLE_ENDIAN);
    assert(view.getShort(0) == 384 && view.position() == 0);

    view.position(1).mark();
    assert(view.putShort(cast(short)-2) is view && view.position() == 3);
    view.order(ByteOrder.BIG_ENDIAN);
    assert(view.putShort(3, cast(short) 0x1234) is view && view.position() == 3);
    assert(view.getShort(3) == 0x1234 && view.reset().position() == 1);
    assert(storage == [85, -128, -2, -1, 0x12, 0x34, 85]);
    auto readOnly = view.asReadOnlyBuffer().order(ByteOrder.LITTLE_ENDIAN);
    assert(readOnly.getShort() == -2 && readOnly.reset().position() == 1);
}

@("Heap ByteBuffer short failures use the two-byte limit and leave the view intact")
unittest
{
    byte[] storage = [0, 1, 2, 3, 4];
    auto view = ByteBuffer.wrap(storage).limit(4).position(3).mark();
    assertThrown!BufferUnderflowException(view.getShort());
    assertThrown!BufferOverflowException(view.putShort(cast(short) 9));
    rejectsMessage!IndexOutOfBoundsException(() { view.getShort(3); }, null);
    rejectsMessage!IndexOutOfBoundsException(() { view.putShort(-1, cast(short) 9); }, null);
    rejectsMessage!IndexOutOfBoundsException(() { ByteBuffer.allocate(0).getShort(0); }, null);

    auto readOnly = view.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.putShort(cast(short) 9));
    assertThrown!ReadOnlyBufferException(readOnly.putShort(-1, cast(short) 9));
    assert(view.position() == 3 && view.reset().position() == 3);
    assert(readOnly.position() == 3 && readOnly.reset().position() == 3);
    assert(storage == [0, 1, 2, 3, 4]);
}
