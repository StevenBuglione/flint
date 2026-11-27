// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 LongBuffer API (pinned against Temurin 21.0.13+9).
module flint.java.nio.long_buffer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException,
    UnsupportedOperationException;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.longbuffer : LongBuffer;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

@("LongBuffer allocate, cursor, mark, rewind and hashCode match Java 21")
unittest
{
    auto badAlloc = collectException!IllegalArgumentException(LongBuffer.allocate(-1));
    assert(badAlloc !is null && badAlloc.getMessage() == "capacity < 0: (-1 < 0)");

    auto buf = LongBuffer.allocate(4);
    assert(buf.capacity() == 4 && buf.position() == 0 && buf.limit() == 4 && buf.remaining() == 4);
    assert(buf.get(0) == 0 && !buf.isReadOnly() && !buf.isDirect() && buf.hasArray() && buf.arrayOffset() == 0);
    assert(buf.order() == ByteOrder.nativeOrder());
    assert(buf.toString() == "java.nio.HeapLongBuffer[pos=0 lim=4 cap=4]");

    buf.put(1L).put(-2L).put(long.max).put(long.min);
    assert(collectException!BufferOverflowException(buf.put(99L)) !is null);
    buf.flip();
    assert(buf.hashCode() == 922_499);
    assert(LongBuffer.wrap([0x1234_5678_9ABC_DEF0L]).hashCode() == -1_698_898_161);
    assert(buf.get() == 1L && buf.get() == -2L && buf.get(2) == long.max && buf.get(3) == long.min);
    assert(buf.position() == 2);
    buf.mark().rewind();
    assert(buf.position() == 0);
    assert(collectException!InvalidMarkException(buf.reset()) !is null);
}

@("LongBuffer slice, duplicate, read-only, wrap and Buffer.array match Java 21")
unittest
{
    auto buf = LongBuffer.allocate(4);
    buf.put(1L).put(-2L).put(long.max).put(long.min);
    buf.position(1).mark().limit(3);

    auto sl = buf.slice();
    assert(sl.capacity() == 2 && sl.arrayOffset() == 1 && sl.get(0) == -2L && sl.get(1) == long.max);
    auto sl2 = buf.slice(1, 2);
    assert(sl2.arrayOffset() == 1 && sl2.get(0) == -2L && sl2.get(1) == long.max);

    auto dup = buf.duplicate();
    assert(dup.position() == 1 && dup.limit() == 3 && dup.equals(buf));
    dup.put(1, 42L);
    assert(buf.get(1) == 42L);

    auto ro = buf.asReadOnlyBuffer();
    assert(ro.isReadOnly() && !ro.hasArray());
    assert(ro.toString() == "java.nio.HeapLongBufferR[pos=1 lim=3 cap=4]");
    assert(buf.equals(ro));
    assert(collectException!ReadOnlyBufferException(ro.array()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.arrayOffset()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0L)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0, 0L)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.compact()) !is null);

    Buffer asBase = sl;
    auto boxed = asBase.array();
    auto raw = boxed.get!(long[])();
    raw[1] = -77L;
    assert(sl.get(0) == -77L);

    long[] backing = [10L, 20L, 30L, 40L];
    auto wrapped = LongBuffer.wrap(backing, 1, 2);
    assert(wrapped.position() == 1 && wrapped.limit() == 3);
    assert(wrapped.get() == 20L && wrapped.get() == 30L);
    assert(collectException!BufferUnderflowException(wrapped.get()) !is null);
    auto badWrap = collectException!IndexOutOfBoundsException(LongBuffer.wrap(backing, -1, 1));
    assert(badWrap !is null && badWrap.getMessage() is null);

    auto emptyNull = LongBuffer.wrap(null);
    assert(emptyNull.capacity() == 0 && emptyNull.hasArray() && emptyNull.array().length == 0);
}

@("LongBuffer bulk array, buffer transfer and compact match Java 21")
unittest
{
    auto buf = LongBuffer.allocate(6);
    const long[] src = [10L, 20L, 30L, 40L];
    buf.put(src);
    buf.put(4, src, 1, 2);
    assert(buf.position() == 4);
    buf.position(0).limit(6);

    long[6] dst;
    buf.get(dst[]);
    assert(dst == [10L, 20L, 30L, 40L, 20L, 30L]);

    long[3] part;
    buf.get(2, part[]);
    assert(part == [30L, 40L, 20L]);
    buf.put(1, part[]);
    assert(buf.get(1) == 30L && buf.get(2) == 40L && buf.get(3) == 20L);

    buf.put(2, buf, 1, 3);
    assert(buf.get(2) == 30L && buf.get(3) == 40L && buf.get(4) == 20L);
    buf.position(2).limit(5).compact();
    assert(buf.position() == 3 && buf.limit() == 6);
    assert(buf.get(0) == 30L && buf.get(1) == 40L && buf.get(2) == 20L);

    auto target = LongBuffer.allocate(4);
    buf.flip();
    target.put(buf);
    assert(target.position() == 3 && !buf.hasRemaining());
    auto selfErr = collectException!IllegalArgumentException(target.put(target));
    assert(selfErr !is null && selfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!NullPointerException(target.put(cast(LongBuffer) null)) !is null);
}

@("LongBuffer byte views, endianness and read-only exception precedence match Java 21")
unittest
{
    byte[] rawBytes = [
        cast(byte) 0x01, cast(byte) 0x02, cast(byte) 0x03, cast(byte) 0x04, cast(byte) 0x05,
        cast(byte) 0x06, cast(byte) 0x07, cast(byte) 0x08, cast(byte) 0xFF, cast(byte) 0xFF,
        cast(byte) 0xFF, cast(byte) 0xFF, cast(byte) 0xFF, cast(byte) 0xFF, cast(byte) 0xFF,
        cast(byte) 0xFF
    ];
    auto viewBE = LongBuffer.ofBytes(rawBytes, false, false);
    assert(viewBE.toString() == "java.nio.ByteBufferAsLongBufferB[pos=0 lim=2 cap=2]");
    assert(viewBE.order() == ByteOrder.BIG_ENDIAN && !viewBE.hasArray());
    assert(collectException!UnsupportedOperationException(viewBE.array()) !is null);
    assert(viewBE.get(0) == 0x0102_0304_0506_0708L && viewBE.get(1) == -1L);

    auto viewLE = LongBuffer.ofBytes(rawBytes, true, false);
    assert(viewLE.toString() == "java.nio.ByteBufferAsLongBufferL[pos=0 lim=2 cap=2]");
    assert(viewLE.order() == ByteOrder.LITTLE_ENDIAN);
    assert(viewLE.get(0) == 0x0807_0605_0403_0201L);

    auto copyDst = LongBuffer.allocate(2);
    copyDst.put(viewBE);
    copyDst.flip();
    assert(copyDst.get(0) == 0x0102_0304_0506_0708L && copyDst.get(1) == -1L);
    viewLE.put(0, copyDst, 0, 2);
    assert(viewLE.get(0) == 0x0102_0304_0506_0708L && viewLE.get(1) == -1L);

    auto heapRO = copyDst.asReadOnlyBuffer();
    auto viewRO = LongBuffer.ofBytes(rawBytes, true, true);
    auto viewROBE = LongBuffer.ofBytes(rawBytes, false, true);
    assert(viewRO.toString() == "java.nio.ByteBufferAsLongBufferRL[pos=0 lim=2 cap=2]");
    assert(viewROBE.toString() == "java.nio.ByteBufferAsLongBufferRB[pos=0 lim=2 cap=2]");

    assert(collectException!ReadOnlyBufferException(heapRO.put(heapRO)) !is null);
    auto viewSelfErr = collectException!IllegalArgumentException(viewRO.put(viewRO));
    assert(viewSelfErr !is null && viewSelfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!ReadOnlyBufferException(viewRO.put(cast(LongBuffer) null)) !is null);
}

@("LongBuffer equals, hashCode, signed compareTo and mismatch match Java 21")
unittest
{
    auto minB = LongBuffer.wrap([long.min]);
    auto maxB = LongBuffer.wrap([long.max]);
    assert(minB.compareTo(maxB) < 0);
    assert(maxB.compareTo(minB) > 0);
    assert(minB.compareTo(LongBuffer.wrap([long.min])) == 0);
    assert(minB.mismatch(LongBuffer.wrap([long.min])) == -1);
    assert(minB.mismatch(maxB) == 0);

    auto prefix = LongBuffer.wrap([1L, 2L]);
    auto longer = LongBuffer.wrap([1L, 2L, 3L]);
    assert(prefix.mismatch(longer) == 2);
    assert(prefix.compareTo(longer) < 0);
    assert(longer.compareTo(prefix) > 0);
    assert(!prefix.equals(longer));
    assert(!prefix.equals(new Object));
    assert(collectException!NullPointerException(prefix.compareTo(null)) !is null);
    assert(collectException!NullPointerException(prefix.mismatch(null)) !is null);
}
