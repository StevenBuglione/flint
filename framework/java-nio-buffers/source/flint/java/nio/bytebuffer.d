/*
 * Copyright (c) 2000, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

/*
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/ByteBuffer.java
 * Includes the corresponding generated HeapByteBuffer behavior.
 * Modified by the Flint authors.
 */
/** Java NIO byte buffers backed by a D byte array. */
module flint.java.nio.bytebuffer;

import core.bitop : bswap;
import flint.engine.aot.any : Any;
import flint.java.lang : Comparable, IllegalArgumentException, JavaObject, NullPointerException;
import flint.java.nio.buffer : Buffer, arraySize, boundMessage, checkIndex, checkRange;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.internal.buffercursor : BufferCursor;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.typecons : Nullable;

@safe:

class ByteBuffer : Buffer, Comparable!ByteBuffer
{
    mixin JavaObject;

    private byte[] backing;
    private int origin;
    private bool readOnly;
    private bool littleEndian;

    private this(byte[] backing, int origin, BufferCursor cursor, bool readOnly) pure nothrow @nogc
    {
        super(cursor);
        this.backing = backing;
        this.origin = origin;
        this.readOnly = readOnly;
    }

    static ByteBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new ByteBuffer(allocateStorage(capacity), 0, BufferCursor(capacity, 0, capacity), false);
    }

    static ByteBuffer wrap(byte[] bytes) pure
    {
        return wrap(bytes, 0, arraySize(bytes.length));
    }

    static ByteBuffer wrap(byte[] bytes, int offset, int length) pure
    {
        const capacity = arraySize(bytes.length);
        checkRange(offset, length, capacity);
        if (bytes is null)
            bytes = allocateStorage(0);
        return new ByteBuffer(bytes, 0, BufferCursor(capacity, offset, offset + length), false);
    }

    alias position = Buffer.position;
    alias limit = Buffer.limit;

    override ByteBuffer position(int position) pure
    {
        super.position(position);
        return this;
    }

    override ByteBuffer limit(int limit) pure
    {
        super.limit(limit);
        return this;
    }

    override ByteBuffer mark() pure nothrow @nogc
    {
        super.mark();
        return this;
    }

    override ByteBuffer reset() pure
    {
        super.reset();
        return this;
    }

    override ByteBuffer clear() pure nothrow @nogc
    {
        super.clear();
        return this;
    }

    override ByteBuffer flip() pure nothrow @nogc
    {
        super.flip();
        return this;
    }

    override ByteBuffer rewind() pure nothrow @nogc
    {
        super.rewind();
        return this;
    }

    override bool isReadOnly() const pure nothrow @nogc
    {
        return readOnly;
    }

    override bool isDirect() const pure nothrow @nogc
    {
        return false;
    }

    override bool hasArray() const pure nothrow @nogc
    {
        return !readOnly;
    }

    byte[] array() pure
    {
        checkWritable();
        return backing;
    }

    protected override Any erasedArray()
    {
        return Any.of(array());
    }

    override int arrayOffset() const pure
    {
        checkWritable();
        return origin;
    }

    ByteOrder order() const pure nothrow @nogc
    {
        return littleEndian ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN;
    }

    ByteBuffer order(ByteOrder value) pure nothrow @nogc
    {
        littleEndian = value != ByteOrder.BIG_ENDIAN;
        return this;
    }

    ByteBuffer order(Nullable!ByteOrder value) pure nothrow @nogc
    {
        return order(value.isNull ? ByteOrder.LITTLE_ENDIAN : value.get());
    }

    override ByteBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override ByteBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new ByteBuffer(backing, origin + index, BufferCursor(length, 0, length), readOnly);
    }

    override ByteBuffer duplicate() pure
    {
        return new ByteBuffer(backing, origin, cursor, readOnly);
    }

    ByteBuffer asReadOnlyBuffer() pure
    {
        return new ByteBuffer(backing, origin, cursor, true);
    }

    ByteBuffer compact() pure
    {
        checkWritable();
        const length = remaining();
        copyFromBuffer(0, this, position(), length);
        cursor.clear();
        advance(length);
        return this;
    }

    byte get() pure
    {
        if (!hasRemaining())
            throwUnderflow();
        const result = backing[origin + position()];
        advance(1);
        return result;
    }

    byte get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return backing[origin + index];
    }

    ByteBuffer get(scope byte[] target, int offset, int length) pure
    {
        checkRange(offset, length, arraySize(target.length));
        if (length > remaining())
            throwUnderflow();
        copyBytes(target, offset, backing, origin + position(), length);
        advance(length);
        return this;
    }

    ByteBuffer get(scope byte[] target) pure
    {
        return get(target, 0, arraySize(target.length));
    }

    ByteBuffer get(int index, scope byte[] target, int offset, int length) pure
    {
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(target.length));
        copyBytes(target, offset, backing, origin + index, length);
        return this;
    }

    ByteBuffer get(int index, scope byte[] target) pure
    {
        return get(index, target, 0, arraySize(target.length));
    }

    ByteBuffer put(byte value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throwOverflow();
        backing[origin + position()] = value;
        advance(1);
        return this;
    }

    ByteBuffer put(int index, byte value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        backing[origin + index] = value;
        return this;
    }

    ByteBuffer put(scope const(byte)[] source, int offset, int length) pure
    {
        checkWritable();
        checkRange(offset, length, arraySize(source.length));
        if (length > remaining())
            throwOverflow();
        copyBytes(backing, origin + position(), source, offset, length);
        advance(length);
        return this;
    }

    final ByteBuffer put(scope const(byte)[] source) pure
    {
        return put(source, 0, arraySize(source.length));
    }

    ByteBuffer put(int index, scope const(byte)[] source, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(source.length));
        copyBytes(backing, origin + index, source, offset, length);
        return this;
    }

    ByteBuffer put(int index, scope const(byte)[] source) pure
    {
        return put(index, source, 0, arraySize(source.length));
    }

    ByteBuffer put(scope ByteBuffer source) pure
    {
        checkWritable();
        if (source is this)
            throw new IllegalArgumentException("The source buffer is this buffer");
        requireBuffer(source);
        const length = source.cursor.remaining();
        if (length > remaining())
            throwOverflow();

        copyFromBuffer(position(), source, source.cursor.position(), length);
        advance(length);
        source.advance(length);
        return this;
    }

    ByteBuffer put(int index, scope ByteBuffer source, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        requireBuffer(source);
        checkRange(offset, length, source.cursor.limit());
        copyFromBuffer(index, source, offset, length);
        return this;
    }

    final CharBuffer asCharBuffer() pure
    {
        return CharBuffer.ofBytes(backing[origin + position() .. origin + limit()], littleEndian, readOnly);
    }

    wchar getChar() pure
    {
        return cast(wchar) readNumber(wchar.sizeof);
    }

    wchar getChar(int index) const pure
    {
        return cast(wchar) readNumber(index, wchar.sizeof);
    }

    ByteBuffer putChar(wchar value) pure
    {
        return putNumber(wchar.sizeof, cast(ulong) value);
    }

    ByteBuffer putChar(int index, wchar value) pure
    {
        return putNumber(index, wchar.sizeof, cast(ulong) value);
    }

    short getShort() pure
    {
        return cast(short) readNumber(short.sizeof);
    }

    short getShort(int index) const pure
    {
        return cast(short) readNumber(index, short.sizeof);
    }

    ByteBuffer putShort(short value) pure
    {
        return putNumber(short.sizeof, cast(ulong) value);
    }

    ByteBuffer putShort(int index, short value) pure
    {
        return putNumber(index, short.sizeof, cast(ulong) value);
    }

    int getInt() pure
    {
        return cast(int) readNumber(int.sizeof);
    }

    int getInt(int index) const pure
    {
        return cast(int) readNumber(index, int.sizeof);
    }

    ByteBuffer putInt(int value) pure
    {
        return putNumber(int.sizeof, cast(ulong) value);
    }

    ByteBuffer putInt(int index, int value) pure
    {
        return putNumber(index, int.sizeof, cast(ulong) value);
    }

    long getLong() pure
    {
        return cast(long) readNumber(long.sizeof);
    }

    long getLong(int index) const pure
    {
        return cast(long) readNumber(index, long.sizeof);
    }

    ByteBuffer putLong(long value) pure
    {
        return putNumber(long.sizeof, cast(ulong) value);
    }

    ByteBuffer putLong(int index, long value) pure
    {
        return putNumber(index, long.sizeof, cast(ulong) value);
    }

    float getFloat() pure
    {
        return FloatBits(cast(uint) readNumber(float.sizeof)).value;
    }

    float getFloat(int index) const pure
    {
        return FloatBits(cast(uint) readNumber(index, float.sizeof)).value;
    }

    ByteBuffer putFloat(float value) pure
    {
        return putNumber(float.sizeof, floatBits(value));
    }

    ByteBuffer putFloat(int index, float value) pure
    {
        return putNumber(index, float.sizeof, floatBits(value));
    }

    double getDouble() pure
    {
        return DoubleBits(readNumber(double.sizeof)).value;
    }

    double getDouble(int index) const pure
    {
        return DoubleBits(readNumber(index, double.sizeof)).value;
    }

    ByteBuffer putDouble(double value) pure
    {
        return putNumber(double.sizeof, doubleBits(value));
    }

    ByteBuffer putDouble(int index, double value) pure
    {
        return putNumber(index, double.sizeof, doubleBits(value));
    }

    bool equals(Object other) pure nothrow @nogc
    {
        if (other is this)
            return true;
        auto buffer = cast(ByteBuffer) other;
        return buffer !is null && remainingBytes() == buffer.remainingBytes();
    }

    int hashCode() const pure nothrow @nogc
    {
        uint hash = 1;
        foreach_reverse (value; remainingBytes())
            hash = hash * 31 + cast(uint) value;
        return cast(int) hash;
    }

    override int compareTo(ByteBuffer other) pure
    {
        requireBuffer(other);
        const left = remainingBytes();
        const right = other.remainingBytes();
        const mismatch = firstMismatch(left, right);
        if (mismatch >= 0 && mismatch < left.length && mismatch < right.length)
            return left[mismatch] - right[mismatch];
        return cast(int) left.length - cast(int) right.length;
    }

    int mismatch(ByteBuffer other) pure
    {
        requireBuffer(other);
        return firstMismatch(remainingBytes(), other.remainingBytes());
    }

    override string toString() pure nothrow
    {
        return summary(readOnly ? "java.nio.HeapByteBufferR" : "java.nio.HeapByteBuffer");
    }

    pragma(inline, false) private ulong readNumber(int width) pure
    {
        if (width > remaining())
            throwUnderflow();
        const value = readNumberAt(position(), width);
        advance(width);
        return value;
    }

    pragma(inline, false) private ulong readNumber(int index, int width) const pure
    {
        checkIndex(index, width, limit());
        return readNumberAt(index, width);
    }

    pragma(inline, false) private ByteBuffer putNumber(int width, ulong value) pure
    {
        checkWritable();
        if (width > remaining())
            throwOverflow();
        writeNumberAt(position(), width, value);
        advance(width);
        return this;
    }

    pragma(inline, false) private ByteBuffer putNumber(int index, int width, ulong value) pure
    {
        checkWritable();
        checkIndex(index, width, limit());
        writeNumberAt(index, width, value);
        return this;
    }

    pragma(inline, false) private ulong readNumberAt(int index, int width) const pure nothrow @nogc
    {
        const start = origin + index;
        const bytes = backing[start .. start + width];
        ulong value;
        foreach (wireByte; bytes)
            value = (value << 8) | cast(ubyte) wireByte;
        return littleEndian ? reverseBytes(value, width) : value;
    }

    pragma(inline, false) private void writeNumberAt(int index, int width, ulong value) pure nothrow @nogc
    {
        const start = origin + index;
        if (!littleEndian)
            value = reverseBytes(value, width);
        foreach (ref wireByte; backing[start .. start + width])
        {
            wireByte = cast(byte) value;
            value >>= 8;
        }
    }

    private void copyFromBuffer(int index, scope ByteBuffer source, int offset, int length) scope pure nothrow @nogc
    {
        pragma(inline, false);
        copyBytes(backing, origin + index, source.backing, source.origin + offset, length);
    }

    private const(byte)[] remainingBytes() const pure nothrow @nogc
    {
        return backing[origin + position() .. origin + limit()];
    }

    private void checkWritable() const pure
    {
        if (readOnly)
            throwReadOnly();
    }

}

pragma(inline, false) private noreturn throwReadOnly() pure
{
    throw new ReadOnlyBufferException;
}

pragma(inline, false) private noreturn throwOverflow() pure
{
    throw new BufferOverflowException;
}

pragma(inline, false) private noreturn throwUnderflow() pure
{
    throw new BufferUnderflowException;
}

private ulong reverseBytes(ulong value, int width) pure nothrow @nogc
{
    // The primitive occupies the low bytes before and after reversing.
    return bswap(value) >> (8 * (ulong.sizeof - width));
}

private union FloatBits
{
    uint bits;
    float value;
}

private union DoubleBits
{
    ulong bits;
    double value;
}

private uint floatBits(float value) pure nothrow @nogc
{
    FloatBits converted;
    converted.value = value;
    return converted.bits;
}

private ulong doubleBits(double value) pure nothrow @nogc
{
    DoubleBits converted;
    converted.value = value;
    return converted.bits;
}

private byte[] allocateStorage(int capacity) pure nothrow
{
    // The erased Java array value distinguishes an empty backing array from null.
    auto bytes = new byte[capacity == 0 ? 1 : capacity];
    return bytes[0 .. capacity];
}

pragma(inline, false) private void copyBytes(scope byte[] target, int targetOffset,
        scope const(byte)[] source, int sourceOffset, int length) pure nothrow @nogc
{
    target = target[targetOffset .. targetOffset + length];
    source = source[sourceOffset .. sourceOffset + length];
    if (target.length == 0 || target.ptr == source.ptr)
        return;

    if (target.ptr > source.ptr && target.ptr <= &source[$ - 1])
    {
        foreach_reverse (i, ref value; target)
            value = source[i];
    }
    else if (source.ptr > target.ptr && source.ptr <= &target[$ - 1])
    {
        foreach (i, ref value; target)
            value = source[i];
    }
    else
    {
        target[] = source[];
    }
}

private int firstMismatch(scope const(byte)[] left, scope const(byte)[] right) pure nothrow @nogc
{
    const common = left.length < right.length ? left.length : right.length;
    foreach (i; 0 .. common)
        if (left[i] != right[i])
            return cast(int) i;
    return left.length == right.length ? -1 : cast(int) common;
}

private void requireBuffer(scope ByteBuffer other) pure
{
    if (other is null)
        throwNullBuffer();
}

pragma(inline, false) private noreturn throwNullBuffer() pure
{
    throw new NullPointerException;
}
