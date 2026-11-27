// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for ByteBuffer typed numeric views (asShort/Int/Long/Float/DoubleBuffer).
module byte_numeric_views_test;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : collectException;

@safe:

private uint floatBits(float value) pure nothrow @nogc
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

private ulong doubleBits(double value) pure nothrow @nogc
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

@("ByteBuffer.asShortBuffer and asIntBuffer share unaligned slices and honor order and read-only")
unittest
{
    auto bb = ByteBuffer.allocate(11).order(ByteOrder.BIG_ENDIAN);
    bb.put(cast(byte) 0xAA); // unaligned offset 1, 10 remaining bytes
    auto sb = bb.asShortBuffer();
    assert(sb.capacity() == 5 && sb.order() == ByteOrder.BIG_ENDIAN && !sb.hasArray());
    assert(sb.toString() == "java.nio.ByteBufferAsShortBufferB[pos=0 lim=5 cap=5]");
    sb.put(cast(short) 0x0102).put(cast(short)-1);
    assert(bb.getShort(1) == 0x0102 && bb.getShort(3) == -1);
    assert(bb.position() == 1); // view mutation does not move ByteBuffer cursor

    auto ib = bb.asIntBuffer(); // 10 remaining bytes -> capacity 2 (2 trailing bytes ignored)
    assert(ib.capacity() == 2 && ib.order() == ByteOrder.BIG_ENDIAN);
    assert(ib.toString() == "java.nio.ByteBufferAsIntBufferB[pos=0 lim=2 cap=2]");
    assert(ib.get(0) == 0x0102_FFFF);

    bb.order(ByteOrder.LITTLE_ENDIAN);
    auto ibLE = bb.asIntBuffer();
    assert(ibLE.order() == ByteOrder.LITTLE_ENDIAN);
    assert(ibLE.toString() == "java.nio.ByteBufferAsIntBufferL[pos=0 lim=2 cap=2]");
    assert(ibLE.get(0) == cast(int) 0xFFFF_0201);

    auto roInt = bb.asReadOnlyBuffer().asIntBuffer(); // asReadOnlyBuffer resets ByteBuffer order to BIG_ENDIAN
    assert(roInt.isReadOnly() && roInt.order() == ByteOrder.BIG_ENDIAN);
    assert(roInt.toString() == "java.nio.ByteBufferAsIntBufferRB[pos=0 lim=2 cap=2]");
    assert(collectException!ReadOnlyBufferException(roInt.put(0, 7)) !is null);
}

@("ByteBuffer.asLongBuffer, asFloatBuffer and asDoubleBuffer honor endianness and raw float/double bits")
unittest
{
    auto bb = ByteBuffer.allocate(17).order(ByteOrder.BIG_ENDIAN);
    bb.position(1); // 16 remaining bytes

    auto lb = bb.asLongBuffer();
    assert(lb.capacity() == 2 && lb.order() == ByteOrder.BIG_ENDIAN);
    assert(lb.toString() == "java.nio.ByteBufferAsLongBufferB[pos=0 lim=2 cap=2]");
    lb.put(0x0102_0304_0506_0708L).put(-1L);
    assert(bb.getLong(1) == 0x0102_0304_0506_0708L && bb.getLong(9) == -1L);

    bb.order(ByteOrder.LITTLE_ENDIAN);
    auto lbLE = bb.asLongBuffer();
    assert(lbLE.toString() == "java.nio.ByteBufferAsLongBufferL[pos=0 lim=2 cap=2]");
    assert(lbLE.get(0) == 0x0807_0605_0403_0201L);

    bb.order(ByteOrder.BIG_ENDIAN);
    bb.putInt(1, 0x3FC0_0000).putInt(5, 0x7FC0_0123);
    auto fb = bb.asFloatBuffer();
    assert(fb.capacity() == 4 && fb.toString() == "java.nio.ByteBufferAsFloatBufferB[pos=0 lim=4 cap=4]");
    assert(fb.get(0) == 1.5f && floatBits(fb.get(1)) == 0x7FC0_0123);

    bb.putLong(1, 0x3FF8_0000_0000_0000L).putLong(9, 0x7FF8_0000_0000_0123L);
    auto db = bb.asDoubleBuffer();
    assert(db.capacity() == 2 && db.toString() == "java.nio.ByteBufferAsDoubleBufferB[pos=0 lim=2 cap=2]");
    assert(db.get(0) == 1.5 && doubleBits(db.get(1)) == 0x7FF8_0000_0000_0123UL);

    auto roDb = bb.asReadOnlyBuffer().order(ByteOrder.LITTLE_ENDIAN).asDoubleBuffer();
    assert(roDb.isReadOnly() && roDb.order() == ByteOrder.LITTLE_ENDIAN);
    assert(roDb.toString() == "java.nio.ByteBufferAsDoubleBufferRL[pos=0 lim=2 cap=2]");
    assert(collectException!ReadOnlyBufferException(roDb.put(0, 2.0)) !is null);
}
