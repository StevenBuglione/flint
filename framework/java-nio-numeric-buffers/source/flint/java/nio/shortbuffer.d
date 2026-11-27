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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/X-Buffer.java.template
 * Includes HeapShortBuffer and heap ByteBufferAsShortBuffer view behavior.
 * Modified by the Flint authors.
 */
/** Java NIO signed 16-bit integers in a short array or a view of heap bytes. */
module flint.java.nio.shortbuffer;

import flint.engine.aot.any : Any;
import flint.java.lang : Comparable, IllegalArgumentException, IndexOutOfBoundsException,
    JavaObject, NullPointerException, UnsupportedOperationException;
import flint.java.nio.buffer : Buffer, arraySize, boundMessage, checkIndex, checkRange;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.internal.buffercursor : BufferCursor;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;

@safe:

class ShortBuffer : Buffer, Comparable!ShortBuffer
{
    mixin JavaObject;

    private enum Storage : ubyte
    {
        shorts,
        bigEndian,
        littleEndian
    }

    private enum ubyte readOnlyFlag = 4;

    private byte[] backing;
    private int origin;
    private ubyte storageFlags;

    private this(byte[] backing, int origin, BufferCursor cursor, ubyte storageFlags) pure nothrow @nogc
    {
        super(cursor);
        this.backing = backing;
        this.origin = origin;
        this.storageFlags = storageFlags;
    }

    package(flint.java.nio) static ShortBuffer ofBytes(byte[] bytes, bool littleEndian, bool readOnly) pure
    {
        const capacity = arraySize(bytes.length / short.sizeof);
        const kind = littleEndian ? Storage.littleEndian : Storage.bigEndian;
        const flags = cast(ubyte)(kind | (readOnly ? readOnlyFlag : 0));
        return new ShortBuffer(bytes, 0, BufferCursor(capacity, 0, capacity), flags);
    }

    static ShortBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new ShortBuffer(cast(byte[]) allocateShorts(capacity), 0, BufferCursor(capacity, 0,
                capacity), Storage.shorts);
    }

    static ShortBuffer wrap(short[] array) pure
    {
        return wrap(array, 0, arraySize(array.length));
    }

    static ShortBuffer wrap(short[] array, int offset, int length) pure
    {
        const capacity = arraySize(array.length);
        if ((offset | length) < 0 || length > capacity - offset)
            throw new IndexOutOfBoundsException;
        if (array is null)
            array = allocateShorts(0);
        return new ShortBuffer(cast(byte[]) array, 0, BufferCursor(capacity, offset, offset + length), Storage.shorts);
    }

    alias position = Buffer.position;
    alias limit = Buffer.limit;

    override ShortBuffer position(int position) pure
    {
        super.position(position);
        return this;
    }

    override ShortBuffer limit(int limit) pure
    {
        super.limit(limit);
        return this;
    }

    override ShortBuffer mark() pure nothrow @nogc
    {
        super.mark();
        return this;
    }

    override ShortBuffer reset() pure
    {
        super.reset();
        return this;
    }

    override ShortBuffer clear() pure nothrow @nogc
    {
        super.clear();
        return this;
    }

    override ShortBuffer flip() pure nothrow @nogc
    {
        super.flip();
        return this;
    }

    override ShortBuffer rewind() pure nothrow @nogc
    {
        super.rewind();
        return this;
    }

    override bool isReadOnly() const pure nothrow @nogc
    {
        return (storageFlags & readOnlyFlag) != 0;
    }

    override bool isDirect() const pure nothrow @nogc
    {
        return false;
    }

    final override bool hasArray() const pure nothrow @nogc
    {
        return storageFlags == Storage.shorts;
    }

    final short[] array() pure
    {
        checkArray();
        return cast(short[]) backing;
    }

    protected override Any erasedArray()
    {
        return Any.of(array());
    }

    final override int arrayOffset() const pure
    {
        checkArray();
        return origin;
    }

    ByteOrder order() const pure nothrow @nogc
    {
        return littleEndian() ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN;
    }

    override ShortBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override ShortBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new ShortBuffer(backing, origin + index, BufferCursor(length, 0, length), storageFlags);
    }

    override ShortBuffer duplicate() pure
    {
        return new ShortBuffer(backing, origin, cursor, storageFlags);
    }

    ShortBuffer asReadOnlyBuffer() pure
    {
        return new ShortBuffer(backing, origin, cursor, cast(ubyte)(storageFlags | readOnlyFlag));
    }

    short get() pure
    {
        if (!hasRemaining())
            throwUnderflow();
        const value = load(position());
        advance(1);
        return value;
    }

    ShortBuffer get(scope short[] dst, int offset, int length) pure
    {
        checkRange(offset, length, arraySize(dst.length));
        if (length > remaining())
            throwUnderflow();
        copyShorts(cast(byte[]) dst[offset .. offset + length], memory(position(), length), needsSwap());
        advance(length);
        return this;
    }

    ShortBuffer get(scope short[] dst) pure
    {
        return get(dst, 0, arraySize(dst.length));
    }

    ShortBuffer get(int index, scope short[] dst, int offset, int length) pure
    {
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(dst.length));
        copyShorts(cast(byte[]) dst[offset .. offset + length], memory(index, length), needsSwap());
        return this;
    }

    ShortBuffer get(int index, scope short[] dst) pure
    {
        return get(index, dst, 0, arraySize(dst.length));
    }

    short get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return load(index);
    }

    ShortBuffer put(short value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throwOverflow();
        store(position(), value);
        advance(1);
        return this;
    }

    ShortBuffer put(int index, short value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        store(index, value);
        return this;
    }

    ShortBuffer put(scope const(short)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(offset, length, arraySize(src.length));
        if (length > remaining())
            throwOverflow();
        copyShorts(memory(position(), length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        advance(length);
        return this;
    }

    final ShortBuffer put(scope const(short)[] src) pure
    {
        return put(src, 0, arraySize(src.length));
    }

    ShortBuffer put(int index, scope const(short)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(src.length));
        copyShorts(memory(index, length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        return this;
    }

    ShortBuffer put(int index, scope const(short)[] src) pure
    {
        return put(index, src, 0, arraySize(src.length));
    }

    ShortBuffer put(scope ShortBuffer src) pure
    {
        if (src is this)
        {
            checkWritableHeap();
            throw new IllegalArgumentException("The source buffer is this buffer");
        }
        checkWritable();
        requireBuffer(src);
        const length = src.cursor.remaining();
        if (length > remaining())
            throwOverflow();

        copyFromBuffer(position(), src, src.cursor.position(), length);
        advance(length);
        src.advance(length);
        return this;
    }

    ShortBuffer put(int index, scope ShortBuffer src, int offset, int length) pure
    {
        checkWritableHeap();
        checkRange(index, length, limit());
        requireBuffer(src);
        checkRange(offset, length, src.cursor.limit());
        checkWritable();
        copyFromBuffer(index, src, offset, length);
        return this;
    }

    ShortBuffer compact() pure
    {
        checkWritable();
        const length = remaining();
        copyFromBuffer(0, this, position(), length);
        cursor.clear();
        advance(length);
        return this;
    }

    bool equals(Object other) pure nothrow @nogc
    {
        if (other is this)
            return true;
        auto that = cast(ShortBuffer) other;
        const length = cursor.remaining();
        return that !is null && length == that.cursor.remaining() && firstMismatch(that, length) < 0;
    }

    int hashCode() const pure nothrow @nogc
    {
        uint hash = 1;
        foreach_reverse (index; cursor.position() .. cursor.limit())
            hash = hash * 31 + cast(uint) cast(int) load(index);
        return cast(int) hash;
    }

    override int compareTo(ShortBuffer other) pure
    {
        requireBuffer(other);
        const left = cursor.remaining();
        const right = other.cursor.remaining();
        const index = firstMismatch(other, left < right ? left : right);
        if (index < 0)
            return left - right;
        const a = load(cursor.position() + index);
        const b = other.load(other.cursor.position() + index);
        return a < b ? -1 : a > b ? 1 : 0;
    }

    int mismatch(ShortBuffer other) pure
    {
        requireBuffer(other);
        const left = cursor.remaining();
        const right = other.cursor.remaining();
        const common = left < right ? left : right;
        const index = firstMismatch(other, common);
        return index < 0 && left != right ? common : index;
    }

    override string toString() const pure nothrow
    {
        return summary(summaryName());
    }

    private string summaryName() const pure nothrow @nogc
    {
        final switch (storageFlags)
        {
        case Storage.shorts:
            return "java.nio.HeapShortBuffer";
        case Storage.shorts | readOnlyFlag:
            return "java.nio.HeapShortBufferR";
        case Storage.bigEndian:
            return "java.nio.ByteBufferAsShortBufferB";
        case Storage.bigEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsShortBufferRB";
        case Storage.littleEndian:
            return "java.nio.ByteBufferAsShortBufferL";
        case Storage.littleEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsShortBufferRL";
        }
    }

    private int firstMismatch(scope const ShortBuffer other, int length) const scope pure nothrow @nogc
    {
        const start = cursor.position();
        const otherStart = other.cursor.position();
        foreach (index; 0 .. length)
            if (load(start + index) != other.load(otherStart + index))
                return index;
        return -1;
    }

    private Storage storageKind() const scope pure nothrow @nogc
    {
        return cast(Storage)(storageFlags & 3);
    }

    private bool littleEndian() const scope pure nothrow @nogc
    {
        const kind = storageKind();
        if (kind == Storage.shorts)
        {
            version (LittleEndian)
                return true;
            else
                return false;
        }
        return kind == Storage.littleEndian;
    }

    private bool needsSwap() const pure nothrow @nogc
    {
        version (LittleEndian)
            return storageKind() == Storage.bigEndian;
        else
            return storageKind() == Storage.littleEndian;
    }

    private byte[] memory(int index, int length) scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * short.sizeof;
        return backing[start .. start + cast(size_t) length * short.sizeof];
    }

    private void copyFromBuffer(int index, scope ShortBuffer source, int offset, int length) pure nothrow @nogc
    {
        copyShorts(memory(index, length), source.memory(offset, length), littleEndian() != source.littleEndian());
    }

    private short load(int index) const scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * short.sizeof;
        const b0 = cast(uint) cast(ubyte) backing[start];
        const b1 = cast(uint) cast(ubyte) backing[start + 1];
        return cast(short)(littleEndian() ? (b0 | (b1 << 8)) : ((b0 << 8) | b1));
    }

    private void store(int index, short value) pure nothrow @nogc
    {
        pragma(inline, false);
        const start = cast(size_t)(origin + index) * short.sizeof;
        const bits = cast(ushort) value;
        const b0 = cast(byte)(bits & 0xFF);
        const b1 = cast(byte)((bits >> 8) & 0xFF);
        if (littleEndian())
        {
            backing[start] = b0;
            backing[start + 1] = b1;
        }
        else
        {
            backing[start] = b1;
            backing[start + 1] = b0;
        }
    }

    pragma(inline, false) private void checkArray() const pure
    {
        if (storageKind() != Storage.shorts)
            throw new UnsupportedOperationException;
        checkWritable();
    }

    pragma(inline, false) private void checkWritableHeap() const pure
    {
        if (storageFlags == (Storage.shorts | readOnlyFlag))
            checkWritable();
    }

    pragma(inline, false) private void checkWritable() const pure
    {
        if ((storageFlags & readOnlyFlag) != 0)
            throw new ReadOnlyBufferException;
    }
}

private void requireBuffer(scope ShortBuffer source) pure
{
    if (source is null)
        throwNullBuffer();
}

pragma(inline, false) private noreturn throwNullBuffer() pure
{
    throw new NullPointerException;
}

pragma(inline, false) private noreturn throwUnderflow() pure
{
    throw new BufferUnderflowException;
}

pragma(inline, false) private noreturn throwOverflow() pure
{
    throw new BufferOverflowException;
}

// A byte view can share a D short array even at an odd byte origin. Follow the
// overlap direction and capture both source bytes before storing either.
private void copyShorts(scope byte[] target, scope const(byte)[] source, bool swap) pure nothrow @nogc
{
    pragma(inline, false);
    if (target.length == 0 || (!swap && target.ptr == source.ptr))
        return;

    if (!swap && (target.ptr > &source[$ - 1] || source.ptr > &target[$ - 1]))
    {
        target[] = source[];
        return;
    }

    const reverse = target.ptr > source.ptr;
    const count = target.length / short.sizeof;
    foreach (word; 0 .. count)
    {
        const offset = (reverse ? count - 1 - word : word) * short.sizeof;
        const b0 = source[offset];
        const b1 = source[offset + 1];
        if (swap)
        {
            target[offset] = b1;
            target[offset + 1] = b0;
        }
        else
        {
            target[offset] = b0;
            target[offset + 1] = b1;
        }
    }
}

private short[] allocateShorts(int capacity) pure nothrow
{
    auto shorts = new short[capacity == 0 ? 1 : capacity];
    return shorts[0 .. capacity];
}
