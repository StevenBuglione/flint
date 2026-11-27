// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 IntBuffer API (pinned against Temurin 21.0.13+9).
module flint.java.nio.int_buffer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException,
    UnsupportedOperationException;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.intbuffer : IntBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

@("IntBuffer allocate, cursor, mark, rewind and hashCode match Java 21")
unittest
{
    auto badAlloc = collectException!IllegalArgumentException(IntBuffer.allocate(-1));
    assert(badAlloc !is null && badAlloc.getMessage() == "capacity < 0: (-1 < 0)");

    auto buf = IntBuffer.allocate(4);
    assert(buf.capacity() == 4 && buf.position() == 0 && buf.limit() == 4 && buf.remaining() == 4);
    assert(!buf.isReadOnly() && !buf.isDirect() && buf.hasArray() && buf.arrayOffset() == 0);
    assert(buf.order() == ByteOrder.nativeOrder());
    assert(buf.toString() == "java.nio.HeapIntBuffer[pos=0 lim=4 cap=4]");

    buf.put(1).put(-2).put(int.max).put(int.min);
    assert(collectException!BufferOverflowException(buf.put(99)) !is null);
    buf.flip();
    assert(buf.hashCode() == 922_499);
    assert(buf.get() == 1 && buf.get() == -2 && buf.get(2) == int.max && buf.get(3) == int.min);
    assert(buf.position() == 2);
    buf.mark().rewind();
    assert(buf.position() == 0);
    assert(collectException!InvalidMarkException(buf.reset()) !is null);
}

@("IntBuffer slice, duplicate, read-only, wrap and Buffer.array match Java 21")
unittest
{
    auto buf = IntBuffer.allocate(4);
    buf.put(1).put(-2).put(int.max).put(int.min);
    buf.position(1).mark().limit(3);

    auto sl = buf.slice();
    assert(sl.capacity() == 2 && sl.arrayOffset() == 1 && sl.get(0) == -2 && sl.get(1) == int.max);
    auto sl2 = buf.slice(1, 2);
    assert(sl2.arrayOffset() == 1 && sl2.get(0) == -2 && sl2.get(1) == int.max);

    auto dup = buf.duplicate();
    assert(dup.position() == 1 && dup.limit() == 3 && dup.equals(buf));
    dup.put(1, 42);
    assert(buf.get(1) == 42);

    auto ro = buf.asReadOnlyBuffer();
    assert(ro.isReadOnly() && !ro.hasArray());
    assert(ro.toString() == "java.nio.HeapIntBufferR[pos=1 lim=3 cap=4]");
    assert(buf.equals(ro));
    assert(collectException!ReadOnlyBufferException(ro.array()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.arrayOffset()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0, 0)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.compact()) !is null);

    Buffer asBase = sl;
    auto boxed = asBase.array();
    auto raw = boxed.get!(int[])();
    raw[1] = -77;
    assert(sl.get(0) == -77);

    auto backing = [10, 20, 30, 40];
    auto wrapped = IntBuffer.wrap(backing, 1, 2);
    assert(wrapped.position() == 1 && wrapped.limit() == 3);
    assert(wrapped.get() == 20 && wrapped.get() == 30);
    assert(collectException!BufferUnderflowException(wrapped.get()) !is null);
    auto badWrap = collectException!IndexOutOfBoundsException(IntBuffer.wrap(backing, -1, 1));
    assert(badWrap !is null && badWrap.getMessage() is null);

    auto emptyNull = IntBuffer.wrap(null);
    assert(emptyNull.capacity() == 0 && emptyNull.hasArray() && emptyNull.array().length == 0);
}

@("IntBuffer bulk array, buffer transfer and compact match Java 21")
unittest
{
    auto buf = IntBuffer.allocate(6);
    const int[] src = [10, 20, 30, 40];
    buf.put(src);
    buf.put(4, src, 1, 2);
    assert(buf.position() == 4);
    buf.position(0).limit(6);

    int[6] dst;
    buf.get(dst[]);
    assert(dst == [10, 20, 30, 40, 20, 30]);

    int[3] part;
    buf.get(2, part[]);
    assert(part == [30, 40, 20]);
    buf.put(1, part[]);
    assert(buf.get(1) == 30 && buf.get(2) == 40 && buf.get(3) == 20);

    buf.put(2, buf, 1, 3);
    assert(buf.get(2) == 30 && buf.get(3) == 40 && buf.get(4) == 20);
    buf.position(2).limit(5).compact();
    assert(buf.position() == 3 && buf.limit() == 6);
    assert(buf.get(0) == 30 && buf.get(1) == 40 && buf.get(2) == 20);

    auto target = IntBuffer.allocate(4);
    buf.flip();
    target.put(buf);
    assert(target.position() == 3 && !buf.hasRemaining());
    auto selfErr = collectException!IllegalArgumentException(target.put(target));
    assert(selfErr !is null && selfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!NullPointerException(target.put(cast(IntBuffer) null)) !is null);
}

@("IntBuffer byte views, endianness and read-only exception precedence match Java 21")
unittest
{
    byte[] rawBytes = [
        cast(byte) 0x01, cast(byte) 0x02, cast(byte) 0x03, cast(byte) 0x04, cast(byte) 0xFF,
        cast(byte) 0xFF, cast(byte) 0xFF, cast(byte) 0xFF, cast(byte) 0x7F, cast(byte) 0x80,
        cast(byte) 0x90, cast(byte) 0xA0
    ];
    auto viewBE = IntBuffer.ofBytes(rawBytes, false, false);
    assert(viewBE.toString() == "java.nio.ByteBufferAsIntBufferB[pos=0 lim=3 cap=3]");
    assert(viewBE.order() == ByteOrder.BIG_ENDIAN && !viewBE.hasArray());
    assert(collectException!UnsupportedOperationException(viewBE.array()) !is null);
    assert(viewBE.get(0) == 0x0102_0304 && viewBE.get(1) == -1 && viewBE.get(2) == 0x7F80_90A0);

    auto viewLE = IntBuffer.ofBytes(rawBytes, true, false);
    assert(viewLE.toString() == "java.nio.ByteBufferAsIntBufferL[pos=0 lim=3 cap=3]");
    assert(viewLE.order() == ByteOrder.LITTLE_ENDIAN);
    assert(viewLE.get(0) == 0x0403_0201);

    auto copyDst = IntBuffer.allocate(3);
    copyDst.put(viewBE);
    copyDst.flip();
    assert(copyDst.get(0) == 0x0102_0304 && copyDst.get(1) == -1 && copyDst.get(2) == 0x7F80_90A0);
    viewLE.put(0, copyDst, 0, 3);
    assert(viewLE.get(0) == 0x0102_0304 && viewLE.get(1) == -1 && viewLE.get(2) == 0x7F80_90A0);

    auto heapRO = copyDst.asReadOnlyBuffer();
    auto viewRO = IntBuffer.ofBytes(rawBytes, true, true);
    auto viewROBE = IntBuffer.ofBytes(rawBytes, false, true);
    assert(viewRO.toString() == "java.nio.ByteBufferAsIntBufferRL[pos=0 lim=3 cap=3]");
    assert(viewROBE.toString() == "java.nio.ByteBufferAsIntBufferRB[pos=0 lim=3 cap=3]");

    assert(collectException!ReadOnlyBufferException(heapRO.put(heapRO)) !is null);
    assert(collectException!ReadOnlyBufferException(heapRO.put(cast(IntBuffer) null)) !is null);
    assert(collectException!ReadOnlyBufferException(heapRO.put(-1, cast(IntBuffer) null, -1, -1)) !is null);
    assert(collectException!ReadOnlyBufferException(heapRO.put([1, 2], -1, 1)) !is null);

    auto viewSelfErr = collectException!IllegalArgumentException(viewRO.put(viewRO));
    assert(viewSelfErr !is null && viewSelfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!ReadOnlyBufferException(viewRO.put(cast(IntBuffer) null)) !is null);
    auto viewRangeErr = collectException!IndexOutOfBoundsException(viewRO.put(-1, cast(IntBuffer) null, -1, -1));
    assert(viewRangeErr !is null && viewRangeErr.getMessage() == "Range [-1, -1 + -1) out of bounds for length 3");
    assert(collectException!ReadOnlyBufferException(viewRO.put([1, 2], -1, 1)) !is null);
}

@("IntBuffer equals, hashCode, signed compareTo and mismatch match Java 21")
unittest
{
    auto minB = IntBuffer.wrap([int.min]);
    auto maxB = IntBuffer.wrap([int.max]);
    assert(minB.compareTo(maxB) < 0);
    assert(maxB.compareTo(minB) > 0);
    assert(minB.compareTo(IntBuffer.wrap([int.min])) == 0);
    assert(minB.mismatch(IntBuffer.wrap([int.min])) == -1);
    assert(minB.mismatch(maxB) == 0);

    auto prefix = IntBuffer.wrap([1, 2]);
    auto longer = IntBuffer.wrap([1, 2, 3]);
    assert(prefix.mismatch(longer) == 2);
    assert(prefix.compareTo(longer) < 0);
    assert(longer.compareTo(prefix) > 0);
    assert(!prefix.equals(longer));
    assert(!prefix.equals(new Object));
    assert(collectException!NullPointerException(prefix.compareTo(null)) !is null);
    assert(collectException!NullPointerException(prefix.mismatch(null)) !is null);
}
