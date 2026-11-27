// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 DoubleBuffer API (pinned against Temurin 21.0.13+9).
module flint.java.nio.double_buffer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException,
    UnsupportedOperationException;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.doublebuffer : DoubleBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

private double fromBits(ulong bits) pure nothrow @nogc
{
    union U
    {
        ulong u;
        double d;
    }

    U x = void;
    x.u = bits;
    return x.d;
}

private ulong toBits(double value) pure nothrow @nogc
{
    union U
    {
        double d;
        ulong u;
    }

    U x = void;
    x.d = value;
    return x.u;
}

@("DoubleBuffer allocate zero-init, cursor, mark, rewind and saturating hashCode match Java 21")
unittest
{
    auto badAlloc = collectException!IllegalArgumentException(DoubleBuffer.allocate(-1));
    assert(badAlloc !is null && badAlloc.getMessage() == "capacity < 0: (-1 < 0)");

    auto buf = DoubleBuffer.allocate(4);
    assert(buf.capacity() == 4 && buf.position() == 0 && buf.limit() == 4 && buf.remaining() == 4);
    assert(buf.get(0) == 0.0 && toBits(buf.get(0)) == 0);
    assert(!buf.isReadOnly() && !buf.isDirect() && buf.hasArray() && buf.arrayOffset() == 0);
    assert(buf.order() == ByteOrder.nativeOrder());
    assert(buf.toString() == "java.nio.HeapDoubleBuffer[pos=0 lim=4 cap=4]");

    buf.put(1.5).put(-2.9).put(double.infinity).put(double.nan);
    assert(collectException!BufferOverflowException(buf.put(99.0)) !is null);
    buf.flip();
    assert(buf.hashCode() == -2_146_561_149);
    assert(DoubleBuffer.wrap([double.nan]).hashCode() == 31);
    assert(DoubleBuffer.wrap([double.infinity]).hashCode() == -2_147_483_618);
    assert(DoubleBuffer.wrap([-double.infinity]).hashCode() == -2_147_483_617);
    assert(DoubleBuffer.wrap([
        1e20, -1e20, cast(double) int.max, cast(double) int.min, 2_147_483_646.9
    ]).hashCode() == -2_120_702_501);

    assert(buf.get() == 1.5 && buf.get() == -2.9 && buf.get(2) == double.infinity);
    const nanVal = buf.get(3);
    assert(nanVal != nanVal);
    assert(buf.position() == 2);
    buf.mark().rewind();
    assert(buf.position() == 0);
    assert(collectException!InvalidMarkException(buf.reset()) !is null);
}

@("DoubleBuffer slice, duplicate, read-only, wrap and Buffer.array match Java 21")
unittest
{
    auto buf = DoubleBuffer.allocate(4);
    buf.put(1.5).put(-2.9).put(3.25).put(4.5);
    buf.position(1).mark().limit(3);

    auto sl = buf.slice();
    assert(sl.capacity() == 2 && sl.arrayOffset() == 1 && sl.get(0) == -2.9 && sl.get(1) == 3.25);
    auto sl2 = buf.slice(1, 2);
    assert(sl2.arrayOffset() == 1 && sl2.get(0) == -2.9 && sl2.get(1) == 3.25);

    auto dup = buf.duplicate();
    assert(dup.position() == 1 && dup.limit() == 3 && dup.equals(buf));
    dup.put(1, 42.5);
    assert(buf.get(1) == 42.5);

    auto ro = buf.asReadOnlyBuffer();
    assert(ro.isReadOnly() && !ro.hasArray());
    assert(ro.toString() == "java.nio.HeapDoubleBufferR[pos=1 lim=3 cap=4]");
    assert(buf.equals(ro));
    assert(collectException!ReadOnlyBufferException(ro.array()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.arrayOffset()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0.0)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0, 0.0)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.compact()) !is null);

    Buffer asBase = sl;
    auto boxed = asBase.array();
    auto raw = boxed.get!(double[])();
    raw[1] = -77.5;
    assert(sl.get(0) == -77.5);

    double[] backing = [10.0, 20.0, 30.0, 40.0];
    auto wrapped = DoubleBuffer.wrap(backing, 1, 2);
    assert(wrapped.position() == 1 && wrapped.limit() == 3);
    assert(wrapped.get() == 20.0 && wrapped.get() == 30.0);
    assert(collectException!BufferUnderflowException(wrapped.get()) !is null);
    auto badWrap = collectException!IndexOutOfBoundsException(DoubleBuffer.wrap(backing, -1, 1));
    assert(badWrap !is null && badWrap.getMessage() is null);

    auto emptyNull = DoubleBuffer.wrap(null);
    assert(emptyNull.capacity() == 0 && emptyNull.hasArray() && emptyNull.array().length == 0);
}

@("DoubleBuffer bulk array, buffer transfer and compact match Java 21")
unittest
{
    auto buf = DoubleBuffer.allocate(6);
    const double[] src = [10.0, 20.0, 30.0, 40.0];
    buf.put(src);
    buf.put(4, src, 1, 2);
    assert(buf.position() == 4);
    buf.position(0).limit(6);

    double[6] dst;
    buf.get(dst[]);
    assert(dst == [10.0, 20.0, 30.0, 40.0, 20.0, 30.0]);

    double[3] part;
    buf.get(2, part[]);
    assert(part == [30.0, 40.0, 20.0]);
    buf.put(1, part[]);
    assert(buf.get(1) == 30.0 && buf.get(2) == 40.0 && buf.get(3) == 20.0);

    buf.put(2, buf, 1, 3);
    assert(buf.get(2) == 30.0 && buf.get(3) == 40.0 && buf.get(4) == 20.0);
    buf.position(2).limit(5).compact();
    assert(buf.position() == 3 && buf.limit() == 6);
    assert(buf.get(0) == 30.0 && buf.get(1) == 40.0 && buf.get(2) == 20.0);

    auto target = DoubleBuffer.allocate(4);
    buf.flip();
    target.put(buf);
    assert(target.position() == 3 && !buf.hasRemaining());
    auto selfErr = collectException!IllegalArgumentException(target.put(target));
    assert(selfErr !is null && selfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!NullPointerException(target.put(cast(DoubleBuffer) null)) !is null);
}

@("DoubleBuffer byte views, raw NaN bits, endianness and read-only precedence match Java 21")
unittest
{
    byte[] rawBytes = [
        cast(byte) 0x3F, cast(byte) 0xF8, cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x00,
        cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x7F, cast(byte) 0xF8,
        cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x01,
        cast(byte) 0x23
    ];
    auto viewBE = DoubleBuffer.ofBytes(rawBytes, false, false);
    assert(viewBE.toString() == "java.nio.ByteBufferAsDoubleBufferB[pos=0 lim=2 cap=2]");
    assert(viewBE.order() == ByteOrder.BIG_ENDIAN && !viewBE.hasArray());
    assert(collectException!UnsupportedOperationException(viewBE.array()) !is null);
    assert(viewBE.get(0) == 1.5 && toBits(viewBE.get(1)) == 0x7FF8_0000_0000_0123UL);

    auto viewLE = DoubleBuffer.ofBytes(rawBytes, true, false);
    assert(viewLE.toString() == "java.nio.ByteBufferAsDoubleBufferL[pos=0 lim=2 cap=2]");
    assert(viewLE.order() == ByteOrder.LITTLE_ENDIAN);
    assert(toBits(viewLE.get(0)) == 0x0000_0000_0000_F83FUL);

    auto copyDst = DoubleBuffer.allocate(2);
    copyDst.put(viewBE);
    copyDst.flip();
    assert(copyDst.get(0) == 1.5 && toBits(copyDst.get(1)) == 0x7FF8_0000_0000_0123UL);
    viewLE.put(0, copyDst, 0, 2);
    assert(viewLE.get(0) == 1.5 && toBits(viewLE.get(1)) == 0x7FF8_0000_0000_0123UL);

    auto heapRO = copyDst.asReadOnlyBuffer();
    auto viewRO = DoubleBuffer.ofBytes(rawBytes, true, true);
    auto viewROBE = DoubleBuffer.ofBytes(rawBytes, false, true);
    assert(viewRO.toString() == "java.nio.ByteBufferAsDoubleBufferRL[pos=0 lim=2 cap=2]");
    assert(viewROBE.toString() == "java.nio.ByteBufferAsDoubleBufferRB[pos=0 lim=2 cap=2]");

    assert(collectException!ReadOnlyBufferException(heapRO.put(heapRO)) !is null);
    auto viewSelfErr = collectException!IllegalArgumentException(viewRO.put(viewRO));
    assert(viewSelfErr !is null && viewSelfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!ReadOnlyBufferException(viewRO.put(cast(DoubleBuffer) null)) !is null);
}

@("DoubleBuffer equals, compareTo and mismatch handle -0.0, +0.0, NaN and infinities per Java 21")
unittest
{
    auto negZero = DoubleBuffer.wrap([-0.0]);
    auto posZero = DoubleBuffer.wrap([+0.0]);
    assert(negZero.equals(posZero));
    assert(negZero.compareTo(posZero) == 0);
    assert(negZero.mismatch(posZero) == -1);

    auto nan1 = DoubleBuffer.wrap([fromBits(0x7FF8_0000_0000_0001UL)]);
    auto nan2 = DoubleBuffer.wrap([fromBits(0x7FF8_0000_0000_0002UL)]);
    auto posInf = DoubleBuffer.wrap([double.infinity]);
    auto negInf = DoubleBuffer.wrap([-double.infinity]);
    assert(nan1.equals(nan2));
    assert(nan1.compareTo(nan2) == 0);
    assert(nan1.mismatch(nan2) == -1);
    assert(nan1.compareTo(posInf) > 0);
    assert(posInf.compareTo(nan1) < 0);
    assert(negInf.compareTo(posInf) < 0);
    assert(nan1.mismatch(posInf) == 0);

    auto prefix = DoubleBuffer.wrap([1.0, 2.0]);
    auto longer = DoubleBuffer.wrap([1.0, 2.0, 3.0]);
    assert(prefix.mismatch(longer) == 2);
    assert(prefix.compareTo(longer) < 0);
    assert(longer.compareTo(prefix) > 0);
    assert(!prefix.equals(longer));
    assert(!prefix.equals(new Object));
    assert(collectException!NullPointerException(prefix.compareTo(null)) !is null);
    assert(collectException!NullPointerException(prefix.mismatch(null)) !is null);
}
