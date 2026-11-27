// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for heap CharBuffer string put overloads.
module char_put_string_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("CharBuffer.put(String) writes UTF-16 units including split supplementary pairs")
unittest
{
    const text = "A\u00E9\u4E2D\U0001F600Z";
    auto buffer = CharBuffer.allocate(8).position(1).mark();
    assert(buffer.put(text, 2, 4) is buffer);
    assert(buffer.position() == 3);
    assert(buffer.get(1) == 0x4E2D && buffer.get(2) == 0xD83D);

    auto loneHigh = buffer.duplicate().position(1).limit(3);
    assert(loneHigh.toString() == "\u4E2D\uFFFD");

    assert(buffer.put(text, 4, 6) is buffer);
    assert(buffer.position() == 5);
    assert(buffer.get(3) == 0xDE00 && buffer.get(4) == 'Z');
    assert(buffer.reset().position() == 1);
    assert(buffer.limit(5).toString() == "\u4E2D\U0001F600Z");

    auto whole = CharBuffer.allocate(6);
    assert(whole.put(text) is whole);
    assert(whole.position() == 6);
    assert(whole.flip().toString() == text);

    // String literals resolve unambiguously to the string overloads.
    auto literal = CharBuffer.allocate(5);
    assert(literal.put("ab") is literal);
    assert(literal.put("cdef", 1, 3) is literal);
    assert(literal.put("") is literal);
    assert(literal.flip().toString() == "abde");
}

@("CharBuffer.put(String) checks range, overflow, read-only, extreme endpoints and R26 null slices")
unittest
{
    wchar[] backing = ['x', 'x', 'x', 'x'];
    auto buffer = CharBuffer.wrap(backing).limit(3).position(1).mark();

    auto err = collectException!IndexOutOfBoundsException(buffer.put("abcd", -1, 2));
    assert(err.getMessage() == "Range [-1, -1 + 3) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", 3, 1));
    assert(err.getMessage() == "Range [3, 3 + -2) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", 1, 5));
    assert(err.getMessage() == "Range [1, 1 + 4) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", 5, 5));
    assert(err.getMessage() == "Range [5, 5 + 0) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", int.min, 1));
    assert(err.getMessage() == "Range [-2147483648, -2147483648 + -2147483647) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", 0, int.min));
    assert(err.getMessage() == "Range [0, 0 + -2147483648) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", int.min, int.max));
    assert(err.getMessage() == "Range [-2147483648, -2147483648 + -1) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", int.max, int.max));
    assert(err.getMessage() == "Range [2147483647, 2147483647 + 0) out of bounds for length 4");
    err = collectException!IndexOutOfBoundsException(buffer.put("abcd", -1, -1));
    assert(err.getMessage() == "Range [-1, -1 + 0) out of bounds for length 4");

    assertThrown!BufferOverflowException(buffer.put("abcd", 0, 4));
    assertThrown!BufferOverflowException(buffer.put("abcd"));
    assert(backing == "xxxx"w);
    assert(buffer.position() == 1 && buffer.reset().position() == 1);

    // Empty slices succeed even on a full buffer; R26 null slices act empty.
    auto full = CharBuffer.allocate(2).position(2);
    assert(full.put("abcd", 4, 4) is full);
    assert(full.put("") is full);
    assert(full.put(cast(const(char)[]) null) is full);
    assert(full.put(cast(const(char)[]) null, 0, 0) is full);
    assertThrown!IndexOutOfBoundsException(full.put(cast(const(char)[]) null, 0, 1));

    // Read-only native heap rejects before range checks (HeapCharBufferR).
    auto readOnly = buffer.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.put("abcd", -1, 2));
    assertThrown!ReadOnlyBufferException(readOnly.put("abcd", 3, 1));
    assertThrown!ReadOnlyBufferException(readOnly.put("abcd", 4, 4));
    assertThrown!ReadOnlyBufferException(readOnly.put(""));
    assertThrown!ReadOnlyBufferException(readOnly.put(cast(const(char)[]) null));
    assertThrown!ReadOnlyBufferException(readOnly.put(cast(const(char)[]) null, 0, 0));
}
