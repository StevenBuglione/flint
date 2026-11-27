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
 * Includes HeapLongBuffer and heap ByteBufferAsLongBuffer view behavior.
 * Modified by the Flint authors.
 */
/** Java NIO signed 64-bit integers in a long array or a view of heap bytes. */
module flint.java.nio.longbuffer;

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

class LongBuffer : Buffer, Comparable!LongBuffer
{
    mixin JavaObject;

    private enum Storage : ubyte
    {
        longs,
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

    package(flint.java.nio) static LongBuffer ofBytes(byte[] bytes, bool littleEndian, bool readOnly) pure
    {
        const capacity = arraySize(bytes.length / long.sizeof);
        const kind = littleEndian ? Storage.littleEndian : Storage.bigEndian;
        const flags = cast(ubyte)(kind | (readOnly ? readOnlyFlag : 0));
        return new LongBuffer(bytes, 0, BufferCursor(capacity, 0, capacity), flags);
    }

    static LongBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new LongBuffer(cast(byte[]) allocateLongs(capacity), 0, BufferCursor(capacity, 0,
                capacity), Storage.longs);
    }

    static LongBuffer wrap(long[] array) pure
    {
        return wrap(array, 0, arraySize(array.length));
    }

    static LongBuffer wrap(long[] array, int offset, int length) pure
    {
        const capacity = arraySize(array.length);
        if ((offset | length) < 0 || length > capacity - offset)
            throw new IndexOutOfBoundsException;
        if (array is null)
            array = allocateLongs(0);
        return new LongBuffer(cast(byte[]) array, 0, BufferCursor(capacity, offset, offset + length), Storage.longs);
    }

    alias position = Buffer.position;
    alias limit = Buffer.limit;

    override LongBuffer position(int position) pure
    {
        super.position(position);
        return this;
    }

    override LongBuffer limit(int limit) pure
    {
        super.limit(limit);
        return this;
    }

    override LongBuffer mark() pure nothrow @nogc
    {
        super.mark();
        return this;
    }

    override LongBuffer reset() pure
    {
        super.reset();
        return this;
    }

    override LongBuffer clear() pure nothrow @nogc
    {
        super.clear();
        return this;
    }

    override LongBuffer flip() pure nothrow @nogc
    {
        super.flip();
        return this;
    }

    override LongBuffer rewind() pure nothrow @nogc
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
        return storageFlags == Storage.longs;
    }

    final long[] array() pure
    {
        checkArray();
        return cast(long[]) backing;
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

    override LongBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override LongBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new LongBuffer(backing, origin + index, BufferCursor(length, 0, length), storageFlags);
    }

    override LongBuffer duplicate() pure
    {
        return new LongBuffer(backing, origin, cursor, storageFlags);
    }

    LongBuffer asReadOnlyBuffer() pure
    {
        return new LongBuffer(backing, origin, cursor, cast(ubyte)(storageFlags | readOnlyFlag));
    }

    long get() pure
    {
        if (!hasRemaining())
            throwUnderflow();
        const value = load(position());
        advance(1);
        return value;
    }

    LongBuffer get(scope long[] dst, int offset, int length) pure
    {
        checkRange(offset, length, arraySize(dst.length));
        if (length > remaining())
            throwUnderflow();
        copyLongs(cast(byte[]) dst[offset .. offset + length], memory(position(), length), needsSwap());
        advance(length);
        return this;
    }

    LongBuffer get(scope long[] dst) pure
    {
        return get(dst, 0, arraySize(dst.length));
    }

    LongBuffer get(int index, scope long[] dst, int offset, int length) pure
    {
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(dst.length));
        copyLongs(cast(byte[]) dst[offset .. offset + length], memory(index, length), needsSwap());
        return this;
    }

    LongBuffer get(int index, scope long[] dst) pure
    {
        return get(index, dst, 0, arraySize(dst.length));
    }

    long get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return load(index);
    }

    LongBuffer put(long value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throwOverflow();
        store(position(), value);
        advance(1);
        return this;
    }

    LongBuffer put(int index, long value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        store(index, value);
        return this;
    }

    LongBuffer put(scope const(long)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(offset, length, arraySize(src.length));
        if (length > remaining())
            throwOverflow();
        copyLongs(memory(position(), length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        advance(length);
        return this;
    }

    final LongBuffer put(scope const(long)[] src) pure
    {
        return put(src, 0, arraySize(src.length));
    }

    LongBuffer put(int index, scope const(long)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(src.length));
        copyLongs(memory(index, length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        return this;
    }

    LongBuffer put(int index, scope const(long)[] src) pure
    {
        return put(index, src, 0, arraySize(src.length));
    }

    LongBuffer put(scope LongBuffer src) pure
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

    LongBuffer put(int index, scope LongBuffer src, int offset, int length) pure
    {
        checkWritableHeap();
        checkRange(index, length, limit());
        requireBuffer(src);
        checkRange(offset, length, src.cursor.limit());
        checkWritable();
        copyFromBuffer(index, src, offset, length);
        return this;
    }

    LongBuffer compact() pure
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
        auto that = cast(LongBuffer) other;
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

    override int compareTo(LongBuffer other) pure
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

    int mismatch(LongBuffer other) pure
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
        case Storage.longs:
            return "java.nio.HeapLongBuffer";
        case Storage.longs | readOnlyFlag:
            return "java.nio.HeapLongBufferR";
        case Storage.bigEndian:
            return "java.nio.ByteBufferAsLongBufferB";
        case Storage.bigEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsLongBufferRB";
        case Storage.littleEndian:
            return "java.nio.ByteBufferAsLongBufferL";
        case Storage.littleEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsLongBufferRL";
        }
    }

    private int firstMismatch(scope const LongBuffer other, int length) const scope pure nothrow @nogc
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
        if (kind == Storage.longs)
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
        const start = cast(size_t)(origin + index) * long.sizeof;
        return backing[start .. start + cast(size_t) length * long.sizeof];
    }

    private void copyFromBuffer(int index, scope LongBuffer source, int offset, int length) pure nothrow @nogc
    {
        copyLongs(memory(index, length), source.memory(offset, length), littleEndian() != source.littleEndian());
    }

    private long load(int index) const scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * long.sizeof;
        ulong bits = 0;
        if (littleEndian())
        {
            foreach (i; 0 .. 8)
                bits |= (cast(ulong) cast(ubyte) backing[start + i]) << (i * 8);
        }
        else
        {
            foreach (i; 0 .. 8)
                bits = (bits << 8) | cast(ulong) cast(ubyte) backing[start + i];
        }
        return cast(long) bits;
    }

    private void store(int index, long value) pure nothrow @nogc
    {
        pragma(inline, false);
        const start = cast(size_t)(origin + index) * long.sizeof;
        const bits = cast(ulong) value;
        if (littleEndian())
        {
            foreach (i; 0 .. 8)
                backing[start + i] = cast(byte)((bits >> (i * 8)) & 0xFF);
        }
        else
        {
            foreach (i; 0 .. 8)
                backing[start + i] = cast(byte)((bits >> ((7 - i) * 8)) & 0xFF);
        }
    }

    pragma(inline, false) private void checkArray() const pure
    {
        if (storageKind() != Storage.longs)
            throw new UnsupportedOperationException;
        checkWritable();
    }

    pragma(inline, false) private void checkWritableHeap() const pure
    {
        if (storageFlags == (Storage.longs | readOnlyFlag))
            checkWritable();
    }

    pragma(inline, false) private void checkWritable() const pure
    {
        if ((storageFlags & readOnlyFlag) != 0)
            throw new ReadOnlyBufferException;
    }
}

private void requireBuffer(scope LongBuffer source) pure
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

// A byte view can share a D long array even at a non-8-byte origin. Follow the
// overlap direction and capture all eight source bytes before storing any.
private void copyLongs(scope byte[] target, scope const(byte)[] source, bool swap) pure nothrow @nogc
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
    const count = target.length / long.sizeof;
    foreach (word; 0 .. count)
    {
        const offset = (reverse ? count - 1 - word : word) * long.sizeof;
        byte[8] bytes = void;
        bytes[] = source[offset .. offset + 8];
        if (swap)
        {
            foreach (i; 0 .. 8)
                target[offset + i] = bytes[7 - i];
        }
        else
        {
            target[offset .. offset + 8] = bytes[];
        }
    }
}

private long[] allocateLongs(int capacity) pure nothrow
{
    auto longs = new long[capacity == 0 ? 1 : capacity];
    return longs[0 .. capacity];
}
