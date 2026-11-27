// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for byte-backed CharBuffer.append(CharSequence), pinned against a Temurin 21.0.13 oracle.
module byte_char_sequence_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

@("Byte-backed CharBuffer.append(text) writes UTF-16 units in the view's byte order")
unittest
{
    auto bytes = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN);
    bytes.asCharBuffer().append("éz");
    assert(bytes.get(0) == -23 && bytes.get(1) == 0 && bytes.get(2) == 122 && bytes.get(3) == 0);

    auto big = ByteBuffer.allocate(4);
    auto chars = big.asCharBuffer();
    assert(chars.append("aéb", 1, 3) is chars && chars.position() == 2);
    assert(big.get(0) == 0 && big.get(1) == -23 && big.get(2) == 0 && big.get(3) == 98);
}

@("A read-only byte-backed CharBuffer checks append's bounds before rejecting the write")
unittest
{
    auto view = ByteBuffer.allocate(8).asCharBuffer().asReadOnlyBuffer();
    auto error = collectException!IndexOutOfBoundsException(view.append("ab", 2, 1));
    assert(error !is null && error.getMessage() == "Range [2, 1) out of bounds for length 2");
    assert(collectException!ReadOnlyBufferException(view.append("ab", 0, 1)) !is null);
    assert(collectException!ReadOnlyBufferException(view.append("ab")) !is null);
}
