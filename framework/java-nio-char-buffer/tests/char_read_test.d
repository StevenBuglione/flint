// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module char_read_test;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

@("Character read checks EOF and a full target before writing")
unittest
{
    auto empty = CharBuffer.allocate(4).position(2).limit(2).mark();
    assert(empty.read(null) == -1 && empty.read(empty) == -1);
    assert(empty.position() == 2 && empty.reset().position() == 2);

    auto source = CharBuffer.allocate(4).position(1).mark();
    auto full = CharBuffer.allocate(3).position(2).limit(2).mark().asReadOnlyBuffer();
    assert(source.read(full) == 0 && full.position() == 2 && full.reset().position() == 2);
    assertThrown!NullPointerException(source.read(null));
    auto self = collectException!IllegalArgumentException(source.read(source));
    assert(self.getMessage() == "The source buffer is this buffer");

    auto readOnly = source.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.read(readOnly));
    auto target = CharBuffer.wrap([cast(wchar) 8]).mark().asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(source.read(target));
    assert(source.position() == 1 && source.limit() == 4 && source.reset().position() == 1);
    assert(target.position() == 0 && target.limit() == 1 && target.reset().position() == 0 && target.get(0) == 8);
}

@("Character read advances both cursors and restores the source limit")
unittest
{
    wchar[] input = [11, 0xD800, 0xFFFF, 0xDC00, 55];
    wchar[] output = [6, 7, 8, 9];
    auto source = CharBuffer.wrap(input).position(1).limit(4).mark().asReadOnlyBuffer();
    auto target = CharBuffer.wrap(output).position(1).limit(3).mark();

    assert(source.read(target) == 2);
    assert(target.position() == 3 && target.limit() == 3 && source.position() == 3 && source.limit() == 4);
    assert(output == [6, 0xD800, 0xFFFF, 9] && target.reset().position() == 1);

    assert(source.read(target) == 1);
    assert(target.position() == 2 && target.limit() == 3 && output == [6, 0xDC00, 0xFFFF, 9]);
    assert(source.position() == 4 && source.limit() == 4 && source.read(target) == -1);
    assert(source.reset().position() == 1 && target.reset().position() == 1);
}
