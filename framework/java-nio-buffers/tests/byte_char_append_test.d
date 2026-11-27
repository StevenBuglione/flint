// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for byte-backed CharBuffer.append(wchar).
module byte_char_append_test;

import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

@("Byte-backed CharBuffer.append(wchar) respects byte order and overflow")
unittest
{
    auto be = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN);
    auto beChars = be.asCharBuffer();
    assert(beChars.append(cast(wchar) 0x1234).append(cast(wchar) 0xD83D) is beChars);
    assert(be.get(0) == cast(byte) 0x12 && be.get(1) == cast(byte) 0x34);
    assert(be.get(2) == cast(byte) 0xD8 && be.get(3) == cast(byte) 0x3D);
    auto overflow = collectException!BufferOverflowException(beChars.append('X'));
    assert(overflow !is null && overflow.getMessage() is null);

    auto le = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN);
    auto leChars = le.asCharBuffer();
    assert(leChars.append(cast(wchar) 0x1234).append(cast(wchar) 0xDC00) is leChars);
    assert(le.get(0) == cast(byte) 0x34 && le.get(1) == cast(byte) 0x12);
    assert(le.get(2) == cast(byte) 0x00 && le.get(3) == cast(byte) 0xDC);
}

@("Read-only byte-backed CharBuffer.append(wchar) rejects writes before overflow")
unittest
{
    auto ro = ByteBuffer.allocate(4).asReadOnlyBuffer().asCharBuffer();
    auto err = collectException!ReadOnlyBufferException(ro.append('A'));
    assert(err !is null && err.getMessage() is null);
    assert(ro.position() == 0);

    ro.position(2);
    err = collectException!ReadOnlyBufferException(ro.append('A'));
    assert(err !is null && err.getMessage() is null);
    assert(ro.position() == 2);
}
