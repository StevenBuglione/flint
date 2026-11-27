// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for CharBuffer.append(wchar).
module char_append_test;

import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("CharBuffer.append(wchar) writes UTF-16 code units and chains like put(wchar)")
unittest
{
    auto buffer = CharBuffer.allocate(3).position(1).mark();
    assert(buffer.append('A').append('\u4E2D') is buffer);
    assert(buffer.position() == 3);
    assert(buffer.get(0) == 0 && buffer.get(1) == 'A' && buffer.get(2) == '\u4E2D');

    auto overflow = collectException!BufferOverflowException(buffer.append('Z'));
    assert(overflow !is null && overflow.getMessage() is null);
    assert(buffer.position() == 3);
    assert(buffer.reset().position() == 1);

    // Slice and surrogate code units append without altering neighboring units.
    wchar[] backing = [0x0011, 0x0022, 0x0033, 0x0044];
    auto view = CharBuffer.wrap(backing, 1, 2).slice();
    assert(view.append(cast(wchar) 0xD83D).append(cast(wchar) 0xDC00) is view);
    assertThrown!BufferOverflowException(view.append('!'));
    assert(backing == [0x0011, 0xD83D, 0xDC00, 0x0044]);
}

@("CharBuffer.append(wchar) rejects read-only buffers before overflow")
unittest
{
    auto ro = CharBuffer.allocate(2).asReadOnlyBuffer();
    auto err = collectException!ReadOnlyBufferException(ro.append('A'));
    assert(err !is null && err.getMessage() is null);
    assert(ro.position() == 0);

    ro.position(2);
    err = collectException!ReadOnlyBufferException(ro.append('A'));
    assert(err !is null && err.getMessage() is null);
    assert(ro.position() == 2);
}
