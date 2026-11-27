// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for CharBuffer.wrap(CharSequence) and append(CharSequence), pinned against a Temurin
// 21.0.13 oracle.
module char_sequence_test;

import flint.java.lang : IndexOutOfBoundsException, UnsupportedOperationException;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

private enum text = "héllo\U0001F600";

private void assertUnits(CharBuffer buffer, int position, int limit, int capacity, scope const(wchar)[] units)
{
    assert(buffer.position() == position && buffer.limit() == limit && buffer.capacity() == capacity);
    foreach (i, unit; units)
        assert(buffer.get(position + cast(int) i) == unit);
}

/// The message of the IndexOutOfBoundsException that `action` throws.
private string boundsMessage(scope void delegate() @safe action)
{
    auto error = collectException!IndexOutOfBoundsException(action());
    assert(error !is null);
    return error.getMessage();
}

@("CharBuffer.wrap(text) holds the UTF-16 units read-only, with no array and native order")
unittest
{
    auto buffer = CharBuffer.wrap(text);
    assertUnits(buffer, 0, 7, 7, [0x68, 0xE9, 0x6C, 0x6C, 0x6F, 0xD83D, 0xDE00]);
    assert(!buffer.hasArray() && buffer.isReadOnly() && !buffer.isDirect());
    assert(buffer.order() is ByteOrder.nativeOrder());
    assert(CharBuffer.wrap(text, 1, 4).toString() == "éll");
    assertUnits(CharBuffer.wrap(""), 0, 0, 0, []);

    auto array = collectException!UnsupportedOperationException(buffer.array());
    assert(array !is null && array.getMessage() is null);
    assert(collectException!UnsupportedOperationException(buffer.arrayOffset()) !is null);
}

@("CharBuffer.wrap(text, start, end) windows, slices and duplicates keep the text backing")
unittest
{
    assertUnits(CharBuffer.wrap(text, 1, 4), 1, 4, 7, [0xE9, 0x6C, 0x6C]);
    assertUnits(CharBuffer.wrap(text, 1, 4).slice(), 0, 3, 3, [0xE9, 0x6C, 0x6C]);
    assertUnits(CharBuffer.wrap(text, 1, 6).subSequence(1, 3), 2, 4, 7, [0x6C, 0x6C]);
    assertUnits(CharBuffer.wrap(text, 6, 7), 6, 7, 7, [0xDE00]);

    auto window = CharBuffer.wrap(text, 2, 5);
    window.get();
    assertUnits(window.duplicate(), 3, 5, 7, [0x6C, 0x6F]);

    auto readOnly = CharBuffer.wrap(text).asReadOnlyBuffer();
    assertUnits(readOnly, 0, 7, 7, [0x68, 0xE9, 0x6C, 0x6C, 0x6F, 0xD83D, 0xDE00]);
    assert(readOnly.isReadOnly() && !readOnly.hasArray());

    auto reading = CharBuffer.wrap(text, 1, 3);
    assert(reading.get() == 0xE9 && reading.get() == 0x6C && reading.remaining() == 0);
    assert(collectException!BufferUnderflowException(CharBuffer.wrap(text, 3, 3).get()) !is null);
    assert(CharBuffer.wrap(text, 1, 4).charAt(2) == 0x6C);

    auto marked = CharBuffer.wrap(text);
    marked.position(2).mark();
    marked.get();
    assert(marked.reset().position() == 2);
}

@("CharBuffer.wrap(text, start, end) rejects bad bounds with a bare IndexOutOfBoundsException")
unittest
{
    foreach (bounds; [[3, 1], [-1, 2], [0, 8]])
    {
        auto error = collectException!IndexOutOfBoundsException(CharBuffer.wrap(text, bounds[0], bounds[1]));
        assert(error !is null && error.getMessage() is null);
    }
}

@("CharBuffer.wrap(text) rejects writes as Java's string-backed buffer does")
unittest
{
    auto wrapped = CharBuffer.wrap(text);
    assert(collectException!ReadOnlyBufferException(wrapped.put('x')) !is null);
    assert(collectException!ReadOnlyBufferException(wrapped.put(9, 'x')) !is null);
    assert(collectException!ReadOnlyBufferException(wrapped.compact()) !is null);
    assert(collectException!ReadOnlyBufferException(wrapped.put("ab")) !is null);
    assert(collectException!ReadOnlyBufferException(wrapped.append("ab")) !is null);
    assert(boundsMessage(() { wrapped.put("ab", 2, 1); }) == "Range [2, 2 + -1) out of bounds for length 2");
    // Java throws StringIndexOutOfBoundsException, a subclass, from String.subSequence.
    assert(boundsMessage(() { wrapped.append("ab", 2, 1); }) == "Range [2, 1) out of bounds for length 2");
}

@("CharBuffer.wrap(text) compares, hashes and transfers like an array-backed buffer")
unittest
{
    wchar[] abc = ['a', 'b', 'c'];
    assert(CharBuffer.wrap("abc").equals(CharBuffer.wrap(abc)));
    assert(CharBuffer.wrap("abc").hashCode() == CharBuffer.wrap(abc).hashCode());
    assert(CharBuffer.wrap("abd").compareTo(CharBuffer.wrap(abc)) == 1);
    wchar[] abxd = ['a', 'b', 'x', 'd'];
    assert(CharBuffer.wrap("abcd").mismatch(CharBuffer.wrap(abxd)) == 2);

    auto target = CharBuffer.allocate(3);
    assert(CharBuffer.wrap(text).read(target) == 3);
    assertUnits(target.flip(), 0, 3, 3, [0x68, 0xE9, 0x6C]);

    auto destination = CharBuffer.allocate(4);
    auto source = CharBuffer.wrap(text, 4, 7);
    destination.put(source);
    assertUnits(destination.flip(), 0, 3, 4, [0x6F, 0xD83D, 0xDE00]);
    assert(source.position() == 7);
}

@("CharBuffer.append(text) and append(text, start, end) write UTF-16 units and chain")
unittest
{
    auto whole = CharBuffer.allocate(8).append("hé\U0001F600").flip();
    assertUnits(whole, 0, 4, 8, [0x68, 0xE9, 0xD83D, 0xDE00]);
    auto window = CharBuffer.allocate(8).append(text, 1, 6).flip();
    assertUnits(window, 0, 5, 8, [0xE9, 0x6C, 0x6C, 0x6F, 0xD83D]);
    assertUnits(CharBuffer.allocate(8).append(text, 5, 6).flip(), 0, 1, 8, [0xD83D]);

    auto buffer = CharBuffer.allocate(4);
    assert(buffer.append("a").append("bc", 1, 2) is buffer);
    assert(buffer.position() == 2);
    assert(CharBuffer.allocate(0).append("").position() == 0);
}

@("CharBuffer.append(text, start, end) checks bounds, then room, as Java's heap buffer does")
unittest
{
    auto heap = CharBuffer.allocate(8);
    assert(boundsMessage(() { heap.append("abc", 2, 1); }) == "Range [2, 1) out of bounds for length 3");
    assert(boundsMessage(() { heap.append("abc", 0, 4); }) == "Range [0, 4) out of bounds for length 3");
    assert(boundsMessage(() { heap.append("abc", -1, 1); }) == "Range [-1, 1) out of bounds for length 3");

    auto small = CharBuffer.allocate(2);
    assert(collectException!BufferOverflowException(small.append("abc")) !is null);
    assert(small.position() == 0);
    assert(collectException!BufferOverflowException(CharBuffer.allocate(1).append("abc", 0, 2)) !is null);
}

@("CharBuffer.append(text) on a read-only heap buffer rejects before checking bounds")
unittest
{
    auto heap = CharBuffer.allocate(4).asReadOnlyBuffer();
    assert(collectException!ReadOnlyBufferException(heap.append("ab")) !is null);
    assert(collectException!ReadOnlyBufferException(heap.append("ab", 2, 1)) !is null);
    assert(collectException!ReadOnlyBufferException(heap.append("ab", 0, 1)) !is null);
}
