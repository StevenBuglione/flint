// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module char_subsequence_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("Character access addresses remaining raw UTF-16 units and preserves the mark")
unittest
{
    wchar[] words = [0xEE, 11, 22, 0xD800, 0xDC00, 0xFFFF, 66, 0xEE];
    auto buffer = CharBuffer.wrap(words).slice(1, 6).position(2).limit(5).mark();
    assert(buffer.length() == 3 && !buffer.isEmpty());
    assert(buffer.charAt(0) == 0xD800 && buffer.charAt(2) == 0xFFFF);
    foreach (index; [-1, 3, int.max])
        assert(collectException!IndexOutOfBoundsException(buffer.charAt(index)).getMessage() is null);
    assert(buffer.position() == 2 && buffer.reset().position() == 2);
}

@("A character subsequence keeps capacity and origin with an independent cursor")
unittest
{
    wchar[] words = [0xEE, 11, 22, 0xD800, 0xDC00, 0xFFFF, 66, 0xEE];
    auto buffer = CharBuffer.wrap(words).slice(1, 6).position(2).limit(5).mark();
    auto sub = buffer.subSequence(1, 3);
    assert(sub.capacity() == 6 && sub.position() == 3 && sub.limit() == 5);
    assert(sub.array() is words && sub.arrayOffset() == 1);
    assert(sub.length() == 2 && sub.charAt(0) == 0xDC00 && sub.charAt(1) == 0xFFFF);
    assertThrown!InvalidMarkException(sub.reset());
    sub.put(3, cast(wchar) 0xCAFE);
    assert(words[4] == 0xCAFE && buffer.charAt(1) == 0xCAFE);
    auto readOnly = buffer.asReadOnlyBuffer().subSequence(1, 2);
    assert(readOnly.isReadOnly() && readOnly.charAt(0) == 0xCAFE && !readOnly.hasArray());
    assertThrown!ReadOnlyBufferException(readOnly.put(3, cast(wchar) 0));
    assertThrown!ReadOnlyBufferException(readOnly.arrayOffset());

    auto empty = buffer.subSequence(3, 3);
    assert(empty.position() == 5 && empty.limit() == 5 && empty.length() == 0 && empty.isEmpty());
    assert(empty.capacity() == 6 && empty.arrayOffset() == 1);
    assertThrown!IndexOutOfBoundsException(empty.charAt(0));
    assert(buffer.position() == 2 && buffer.reset().position() == 2);
    assert(words[0] == 0xEE && words[7] == 0xEE);
}

@("Invalid subsequence endpoints preserve state and report the inclusive-exclusive range")
unittest
{
    auto buffer = CharBuffer.allocate(7).position(2).limit(5).mark();
    auto e = collectException!IndexOutOfBoundsException(buffer.subSequence(-1, 0));
    assert(e.getMessage() == "Range [-1, 0) out of bounds for length 3");
    e = collectException!IndexOutOfBoundsException(buffer.subSequence(2, 1));
    assert(e.getMessage() == "Range [2, 1) out of bounds for length 3");
    e = collectException!IndexOutOfBoundsException(buffer.subSequence(0, 4));
    assert(e.getMessage() == "Range [0, 4) out of bounds for length 3");
    e = collectException!IndexOutOfBoundsException(buffer.subSequence(int.max, int.min));
    assert(e.getMessage() == "Range [2147483647, -2147483648) out of bounds for length 3");
    assert(buffer.position() == 2 && buffer.limit() == 5 && buffer.reset().position() == 2);
}
