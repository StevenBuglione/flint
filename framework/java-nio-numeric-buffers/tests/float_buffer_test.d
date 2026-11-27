// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 FloatBuffer API (pinned against Temurin 21.0.13+9).
module flint.java.nio.float_buffer_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException,
    UnsupportedOperationException;
import flint.java.nio.buffer : Buffer;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.floatbuffer : FloatBuffer;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

private float fromBits(uint bits) pure nothrow @nogc
{
    union U
    {
        uint u;
        float f;
    }

    U x = void;
    x.u = bits;
    return x.f;
}

private uint toBits(float value) pure nothrow @nogc
{
    union U
    {
        float f;
        uint u;
    }

    U x = void;
    x.f = value;
    return x.u;
}

@("FloatBuffer allocate zero-init, cursor, mark, rewind and saturating hashCode match Java 21")
unittest
{
    auto badAlloc = collectException!IllegalArgumentException(FloatBuffer.allocate(-1));
    assert(badAlloc !is null && badAlloc.getMessage() == "capacity < 0: (-1 < 0)");

    auto buf = FloatBuffer.allocate(4);
    assert(buf.capacity() == 4 && buf.position() == 0 && buf.limit() == 4 && buf.remaining() == 4);
    assert(buf.get(0) == 0.0f && toBits(buf.get(0)) == 0);
    assert(!buf.isReadOnly() && !buf.isDirect() && buf.hasArray() && buf.arrayOffset() == 0);
    assert(buf.order() == ByteOrder.nativeOrder());
    assert(buf.toString() == "java.nio.HeapFloatBuffer[pos=0 lim=4 cap=4]");

    buf.put(1.5f).put(-2.9f).put(float.infinity).put(float.nan);
    assert(collectException!BufferOverflowException(buf.put(99.0f)) !is null);
    buf.flip();
    assert(buf.hashCode() == -2_146_561_149);
    assert(FloatBuffer.wrap([float.nan]).hashCode() == 31);
    assert(FloatBuffer.wrap([float.infinity]).hashCode() == -2_147_483_618);
    assert(FloatBuffer.wrap([-float.infinity]).hashCode() == -2_147_483_617);
    assert(FloatBuffer.wrap([1e20f, -1e20f, 2_147_483_648.0f, -2_147_483_648.0f,
            2_147_483_520.0f]).hashCode() == 2_057_901_149);

    assert(buf.get() == 1.5f && buf.get() == -2.9f && buf.get(2) == float.infinity);
    const nanVal = buf.get(3);
    assert(nanVal != nanVal);
    assert(buf.position() == 2);
    buf.mark().rewind();
    assert(buf.position() == 0);
    assert(collectException!InvalidMarkException(buf.reset()) !is null);
}

@("FloatBuffer slice, duplicate, read-only, wrap and Buffer.array match Java 21")
unittest
{
    auto buf = FloatBuffer.allocate(4);
    buf.put(1.5f).put(-2.9f).put(3.25f).put(4.5f);
    buf.position(1).mark().limit(3);

    auto sl = buf.slice();
    assert(sl.capacity() == 2 && sl.arrayOffset() == 1 && sl.get(0) == -2.9f && sl.get(1) == 3.25f);
    auto sl2 = buf.slice(1, 2);
    assert(sl2.arrayOffset() == 1 && sl2.get(0) == -2.9f && sl2.get(1) == 3.25f);

    auto dup = buf.duplicate();
    assert(dup.position() == 1 && dup.limit() == 3 && dup.equals(buf));
    dup.put(1, 42.5f);
    assert(buf.get(1) == 42.5f);

    auto ro = buf.asReadOnlyBuffer();
    assert(ro.isReadOnly() && !ro.hasArray());
    assert(ro.toString() == "java.nio.HeapFloatBufferR[pos=1 lim=3 cap=4]");
    assert(buf.equals(ro));
    assert(collectException!ReadOnlyBufferException(ro.array()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.arrayOffset()) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0.0f)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.put(0, 0.0f)) !is null);
    assert(collectException!ReadOnlyBufferException(ro.compact()) !is null);

    Buffer asBase = sl;
    auto boxed = asBase.array();
    auto raw = boxed.get!(float[])();
    raw[1] = -77.5f;
    assert(sl.get(0) == -77.5f);

    float[] backing = [10.0f, 20.0f, 30.0f, 40.0f];
    auto wrapped = FloatBuffer.wrap(backing, 1, 2);
    assert(wrapped.position() == 1 && wrapped.limit() == 3);
    assert(wrapped.get() == 20.0f && wrapped.get() == 30.0f);
    assert(collectException!BufferUnderflowException(wrapped.get()) !is null);
    auto badWrap = collectException!IndexOutOfBoundsException(FloatBuffer.wrap(backing, -1, 1));
    assert(badWrap !is null && badWrap.getMessage() is null);

    auto emptyNull = FloatBuffer.wrap(null);
    assert(emptyNull.capacity() == 0 && emptyNull.hasArray() && emptyNull.array().length == 0);
}

@("FloatBuffer bulk array, buffer transfer and compact match Java 21")
unittest
{
    auto buf = FloatBuffer.allocate(6);
    const float[] src = [10.0f, 20.0f, 30.0f, 40.0f];
    buf.put(src);
    buf.put(4, src, 1, 2);
    assert(buf.position() == 4);
    buf.position(0).limit(6);

    float[6] dst;
    buf.get(dst[]);
    assert(dst == [10.0f, 20.0f, 30.0f, 40.0f, 20.0f, 30.0f]);

    float[3] part;
    buf.get(2, part[]);
    assert(part == [30.0f, 40.0f, 20.0f]);
    buf.put(1, part[]);
    assert(buf.get(1) == 30.0f && buf.get(2) == 40.0f && buf.get(3) == 20.0f);

    buf.put(2, buf, 1, 3);
    assert(buf.get(2) == 30.0f && buf.get(3) == 40.0f && buf.get(4) == 20.0f);
    buf.position(2).limit(5).compact();
    assert(buf.position() == 3 && buf.limit() == 6);
    assert(buf.get(0) == 30.0f && buf.get(1) == 40.0f && buf.get(2) == 20.0f);

    auto target = FloatBuffer.allocate(4);
    buf.flip();
    target.put(buf);
    assert(target.position() == 3 && !buf.hasRemaining());
    auto selfErr = collectException!IllegalArgumentException(target.put(target));
    assert(selfErr !is null && selfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!NullPointerException(target.put(cast(FloatBuffer) null)) !is null);
}

@("FloatBuffer byte views, raw NaN bits, endianness and read-only precedence match Java 21")
unittest
{
    byte[] rawBytes = [
        cast(byte) 0x3F, cast(byte) 0xC0, cast(byte) 0x00, cast(byte) 0x00, cast(byte) 0x7F,
        cast(byte) 0xC0, cast(byte) 0x01, cast(byte) 0x23
    ];
    auto viewBE = FloatBuffer.ofBytes(rawBytes, false, false);
    assert(viewBE.toString() == "java.nio.ByteBufferAsFloatBufferB[pos=0 lim=2 cap=2]");
    assert(viewBE.order() == ByteOrder.BIG_ENDIAN && !viewBE.hasArray());
    assert(collectException!UnsupportedOperationException(viewBE.array()) !is null);
    assert(viewBE.get(0) == 1.5f && toBits(viewBE.get(1)) == 0x7FC0_0123);

    auto viewLE = FloatBuffer.ofBytes(rawBytes, true, false);
    assert(viewLE.toString() == "java.nio.ByteBufferAsFloatBufferL[pos=0 lim=2 cap=2]");
    assert(viewLE.order() == ByteOrder.LITTLE_ENDIAN);
    assert(toBits(viewLE.get(0)) == 0x0000_C03F);

    auto copyDst = FloatBuffer.allocate(2);
    copyDst.put(viewBE);
    copyDst.flip();
    assert(copyDst.get(0) == 1.5f && toBits(copyDst.get(1)) == 0x7FC0_0123);
    viewLE.put(0, copyDst, 0, 2);
    assert(viewLE.get(0) == 1.5f && toBits(viewLE.get(1)) == 0x7FC0_0123);

    auto heapRO = copyDst.asReadOnlyBuffer();
    auto viewRO = FloatBuffer.ofBytes(rawBytes, true, true);
    auto viewROBE = FloatBuffer.ofBytes(rawBytes, false, true);
    assert(viewRO.toString() == "java.nio.ByteBufferAsFloatBufferRL[pos=0 lim=2 cap=2]");
    assert(viewROBE.toString() == "java.nio.ByteBufferAsFloatBufferRB[pos=0 lim=2 cap=2]");

    assert(collectException!ReadOnlyBufferException(heapRO.put(heapRO)) !is null);
    auto viewSelfErr = collectException!IllegalArgumentException(viewRO.put(viewRO));
    assert(viewSelfErr !is null && viewSelfErr.getMessage() == "The source buffer is this buffer");
    assert(collectException!ReadOnlyBufferException(viewRO.put(cast(FloatBuffer) null)) !is null);
}

@("FloatBuffer equals, compareTo and mismatch handle -0.0, +0.0, NaN and infinities per Java 21")
unittest
{
    auto negZero = FloatBuffer.wrap([-0.0f]);
    auto posZero = FloatBuffer.wrap([+0.0f]);
    assert(negZero.equals(posZero));
    assert(negZero.compareTo(posZero) == 0);
    assert(negZero.mismatch(posZero) == -1);

    auto nan1 = FloatBuffer.wrap([fromBits(0x7FC0_0001)]);
    auto nan2 = FloatBuffer.wrap([fromBits(0x7FC0_0002)]);
    auto posInf = FloatBuffer.wrap([float.infinity]);
    auto negInf = FloatBuffer.wrap([-float.infinity]);
    assert(nan1.equals(nan2));
    assert(nan1.compareTo(nan2) == 0);
    assert(nan1.mismatch(nan2) == -1);
    assert(nan1.compareTo(posInf) > 0);
    assert(posInf.compareTo(nan1) < 0);
    assert(negInf.compareTo(posInf) < 0);
    assert(nan1.mismatch(posInf) == 0);

    auto prefix = FloatBuffer.wrap([1.0f, 2.0f]);
    auto longer = FloatBuffer.wrap([1.0f, 2.0f, 3.0f]);
    assert(prefix.mismatch(longer) == 2);
    assert(prefix.compareTo(longer) < 0);
    assert(longer.compareTo(prefix) > 0);
    assert(!prefix.equals(longer));
    assert(!prefix.equals(new Object));
    assert(collectException!NullPointerException(prefix.compareTo(null)) !is null);
    assert(collectException!NullPointerException(prefix.mismatch(null)) !is null);
}
