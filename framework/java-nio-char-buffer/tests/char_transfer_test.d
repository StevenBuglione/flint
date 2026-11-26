// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module char_transfer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("Heap character buffer puts copy both overlap directions and preserve marks")
unittest
{
    wchar[] storage = [1, 2, 3, 4, 5, 6];
    auto into = CharBuffer.wrap(storage).position(1).limit(5).mark();
    auto from = into.duplicate().position(0).limit(3).mark().asReadOnlyBuffer();

    assert(into.put(from) is into);
    assert(storage == [1, 1, 2, 3, 5, 6]);
    assert(into.position() == 4 && from.position() == 3);
    assert(into.reset().position() == 1 && from.reset().position() == 0);
    assert(into.put(0, into, 1, 3) is into);
    assert(storage == [1, 2, 3, 3, 5, 6] && into.reset().position() == 1);
    assert(into.put(5, from, 3, 0) is into && from.position() == 0);
    assert(into.put(from.position(3)) is into && into.position() == 1);
}

@("Heap character buffer puts reject before copying or changing either cursor")
unittest
{
    wchar[] storage = [1, 2, 3, 4, 5, 6];
    auto into = CharBuffer.wrap(storage).limit(5).position(1).mark();
    auto from = CharBuffer.allocate(6).limit(5).mark();
    auto absent = cast(CharBuffer) null;

    auto self = collectException!IllegalArgumentException(into.put(into));
    assert(self.getMessage() == "The source buffer is this buffer");
    assertThrown!NullPointerException(into.put(absent));
    assertThrown!NullPointerException(into.put(0, absent, 0, 0));
    auto range = collectException!IndexOutOfBoundsException(into.put(-1, absent, -1, 2));
    assert(range.getMessage() == "Range [-1, -1 + 2) out of bounds for length 5");
    range = collectException!IndexOutOfBoundsException(into.put(0, from, 4, 2));
    assert(range.getMessage() == "Range [4, 4 + 2) out of bounds for length 5");
    assertThrown!BufferOverflowException(into.put(from));

    auto readOnly = into.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.put(readOnly));
    assertThrown!ReadOnlyBufferException(readOnly.put(absent));
    assertThrown!ReadOnlyBufferException(readOnly.put(-1, absent, 0, 0));
    assertThrown!ReadOnlyBufferException(readOnly.put(0, absent, 0, 0));
    assertThrown!ReadOnlyBufferException(readOnly.put(0, from, 5, 1));
    assert(readOnly.position() == 1 && readOnly.reset().position() == 1);
    assert(into.position() == 1 && into.reset().position() == 1);
    assert(from.position() == 0 && from.reset().position() == 0);
    assert(storage == [1, 2, 3, 4, 5, 6]);
}

@("Heap character compact moves only remaining units and discards even an empty mark")
unittest
{
    wchar[] storage = [99, 1, 2, 3, 4, 5, 98];
    auto buffer = CharBuffer.wrap(storage).slice(1, 5).limit(4).position(1).mark();
    auto readOnly = buffer.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.compact());
    assert(readOnly.position() == 1 && readOnly.reset().position() == 1);
    assert(storage == [99, 1, 2, 3, 4, 5, 98]);

    assert(buffer.compact() is buffer);
    assert(buffer.position() == 3 && buffer.limit() == 5);
    assert(storage == [99, 2, 3, 4, 4, 5, 98]);
    assertThrown!InvalidMarkException(buffer.reset());

    assert(buffer.position(5).mark().compact() is buffer);
    assert(buffer.position() == 0 && buffer.limit() == 5);
    assert(storage == [99, 2, 3, 4, 4, 5, 98]);
    assertThrown!InvalidMarkException(buffer.reset());
}
