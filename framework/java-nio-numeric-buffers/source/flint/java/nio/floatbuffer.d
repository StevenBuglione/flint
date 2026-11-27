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
 * Includes HeapFloatBuffer and heap ByteBufferAsFloatBuffer view behavior.
 * Modified by the Flint authors.
 */
/** Java NIO IEEE 754 32-bit floats in a float array or a view of heap bytes. */
module flint.java.nio.floatbuffer;

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

class FloatBuffer : Buffer, Comparable!FloatBuffer
{
    mixin JavaObject;

    private enum Storage : ubyte
    {
        floats,
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

    package(flint.java.nio) static FloatBuffer ofBytes(byte[] bytes, bool littleEndian, bool readOnly) pure
    {
        const capacity = arraySize(bytes.length / float.sizeof);
        const kind = littleEndian ? Storage.littleEndian : Storage.bigEndian;
        const flags = cast(ubyte)(kind | (readOnly ? readOnlyFlag : 0));
        return new FloatBuffer(bytes, 0, BufferCursor(capacity, 0, capacity), flags);
    }

    static FloatBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new FloatBuffer(cast(byte[]) allocateFloats(capacity), 0, BufferCursor(capacity, 0,
                capacity), Storage.floats);
    }

    static FloatBuffer wrap(float[] array) pure
    {
        return wrap(array, 0, arraySize(array.length));
    }

    static FloatBuffer wrap(float[] array, int offset, int length) pure
    {
        const capacity = arraySize(array.length);
        if ((offset | length) < 0 || length > capacity - offset)
            throw new IndexOutOfBoundsException;
        if (array is null)
            array = allocateFloats(0);
        return new FloatBuffer(cast(byte[]) array, 0, BufferCursor(capacity, offset, offset + length), Storage.floats);
    }

    alias position = Buffer.position;
    alias limit = Buffer.limit;

    override FloatBuffer position(int position) pure
    {
        super.position(position);
        return this;
    }

    override FloatBuffer limit(int limit) pure
    {
        super.limit(limit);
        return this;
    }

    override FloatBuffer mark() pure nothrow @nogc
    {
        super.mark();
        return this;
    }

    override FloatBuffer reset() pure
    {
        super.reset();
        return this;
    }

    override FloatBuffer clear() pure nothrow @nogc
    {
        super.clear();
        return this;
    }

    override FloatBuffer flip() pure nothrow @nogc
    {
        super.flip();
        return this;
    }

    override FloatBuffer rewind() pure nothrow @nogc
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
        return storageFlags == Storage.floats;
    }

    final float[] array() pure
    {
        checkArray();
        return cast(float[]) backing;
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

    override FloatBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override FloatBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new FloatBuffer(backing, origin + index, BufferCursor(length, 0, length), storageFlags);
    }

    override FloatBuffer duplicate() pure
    {
        return new FloatBuffer(backing, origin, cursor, storageFlags);
    }

    FloatBuffer asReadOnlyBuffer() pure
    {
        return new FloatBuffer(backing, origin, cursor, cast(ubyte)(storageFlags | readOnlyFlag));
    }

    float get() pure
    {
        if (!hasRemaining())
            throwUnderflow();
        const value = load(position());
        advance(1);
        return value;
    }

    FloatBuffer get(scope float[] dst, int offset, int length) pure
    {
        checkRange(offset, length, arraySize(dst.length));
        if (length > remaining())
            throwUnderflow();
        copyFloats(cast(byte[]) dst[offset .. offset + length], memory(position(), length), needsSwap());
        advance(length);
        return this;
    }

    FloatBuffer get(scope float[] dst) pure
    {
        return get(dst, 0, arraySize(dst.length));
    }

    FloatBuffer get(int index, scope float[] dst, int offset, int length) pure
    {
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(dst.length));
        copyFloats(cast(byte[]) dst[offset .. offset + length], memory(index, length), needsSwap());
        return this;
    }

    FloatBuffer get(int index, scope float[] dst) pure
    {
        return get(index, dst, 0, arraySize(dst.length));
    }

    float get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return load(index);
    }

    FloatBuffer put(float value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throwOverflow();
        store(position(), value);
        advance(1);
        return this;
    }

    FloatBuffer put(int index, float value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        store(index, value);
        return this;
    }

    FloatBuffer put(scope const(float)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(offset, length, arraySize(src.length));
        if (length > remaining())
            throwOverflow();
        copyFloats(memory(position(), length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        advance(length);
        return this;
    }

    final FloatBuffer put(scope const(float)[] src) pure
    {
        return put(src, 0, arraySize(src.length));
    }

    FloatBuffer put(int index, scope const(float)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(src.length));
        copyFloats(memory(index, length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        return this;
    }

    FloatBuffer put(int index, scope const(float)[] src) pure
    {
        return put(index, src, 0, arraySize(src.length));
    }

    FloatBuffer put(scope FloatBuffer src) pure
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

    FloatBuffer put(int index, scope FloatBuffer src, int offset, int length) pure
    {
        checkWritableHeap();
        checkRange(index, length, limit());
        requireBuffer(src);
        checkRange(offset, length, src.cursor.limit());
        checkWritable();
        copyFromBuffer(index, src, offset, length);
        return this;
    }

    FloatBuffer compact() pure
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
        auto that = cast(FloatBuffer) other;
        const length = cursor.remaining();
        return that !is null && length == that.cursor.remaining() && firstMismatch(that, length) < 0;
    }

    int hashCode() const pure nothrow @nogc
    {
        uint hash = 1;
        foreach_reverse (index; cursor.position() .. cursor.limit())
            hash = hash * 31 + cast(uint) floatToJavaInt(load(index));
        return cast(int) hash;
    }

    override int compareTo(FloatBuffer other) pure
    {
        requireBuffer(other);
        const left = cursor.remaining();
        const right = other.cursor.remaining();
        const index = firstMismatch(other, left < right ? left : right);
        if (index < 0)
            return left - right;
        return compareFloat(load(cursor.position() + index), other.load(other.cursor.position() + index));
    }

    int mismatch(FloatBuffer other) pure
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
        case Storage.floats:
            return "java.nio.HeapFloatBuffer";
        case Storage.floats | readOnlyFlag:
            return "java.nio.HeapFloatBufferR";
        case Storage.bigEndian:
            return "java.nio.ByteBufferAsFloatBufferB";
        case Storage.bigEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsFloatBufferRB";
        case Storage.littleEndian:
            return "java.nio.ByteBufferAsFloatBufferL";
        case Storage.littleEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsFloatBufferRL";
        }
    }

    private int firstMismatch(scope const FloatBuffer other, int length) const scope pure nothrow @nogc
    {
        const start = cursor.position();
        const otherStart = other.cursor.position();
        foreach (index; 0 .. length)
        {
            const a = load(start + index);
            const b = other.load(otherStart + index);
            if (!(a == b || (a != a && b != b)))
                return index;
        }
        return -1;
    }

    private Storage storageKind() const scope pure nothrow @nogc
    {
        return cast(Storage)(storageFlags & 3);
    }

    private bool littleEndian() const scope pure nothrow @nogc
    {
        const kind = storageKind();
        if (kind == Storage.floats)
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
        const start = cast(size_t)(origin + index) * float.sizeof;
        return backing[start .. start + cast(size_t) length * float.sizeof];
    }

    private void copyFromBuffer(int index, scope FloatBuffer source, int offset, int length) pure nothrow @nogc
    {
        copyFloats(memory(index, length), source.memory(offset, length), littleEndian() != source.littleEndian());
    }

    private float load(int index) const scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * float.sizeof;
        const b0 = cast(uint) cast(ubyte) backing[start];
        const b1 = cast(uint) cast(ubyte) backing[start + 1];
        const b2 = cast(uint) cast(ubyte) backing[start + 2];
        const b3 = cast(uint) cast(ubyte) backing[start + 3];
        const bits = littleEndian() ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) : ((b0 << 24) | (b1 << 16) | (
                b2 << 8) | b3);
        return bitsToFloat(bits);
    }

    private void store(int index, float value) pure nothrow @nogc
    {
        pragma(inline, false);
        const start = cast(size_t)(origin + index) * float.sizeof;
        const bits = floatToBits(value);
        const b0 = cast(byte)(bits & 0xFF);
        const b1 = cast(byte)((bits >> 8) & 0xFF);
        const b2 = cast(byte)((bits >> 16) & 0xFF);
        const b3 = cast(byte)((bits >> 24) & 0xFF);
        if (littleEndian())
        {
            backing[start] = b0;
            backing[start + 1] = b1;
            backing[start + 2] = b2;
            backing[start + 3] = b3;
        }
        else
        {
            backing[start] = b3;
            backing[start + 1] = b2;
            backing[start + 2] = b1;
            backing[start + 3] = b0;
        }
    }

    pragma(inline, false) private void checkArray() const pure
    {
        if (storageKind() != Storage.floats)
            throw new UnsupportedOperationException;
        checkWritable();
    }

    pragma(inline, false) private void checkWritableHeap() const pure
    {
        if (storageFlags == (Storage.floats | readOnlyFlag))
            checkWritable();
    }

    pragma(inline, false) private void checkWritable() const pure
    {
        if ((storageFlags & readOnlyFlag) != 0)
            throw new ReadOnlyBufferException;
    }
}

private void requireBuffer(scope FloatBuffer source) pure
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

private float bitsToFloat(uint bits) pure nothrow @nogc
{
    union FloatBits
    {
        uint bits;
        float value;
    }

    FloatBits raw = void;
    raw.bits = bits;
    return raw.value;
}

private uint floatToBits(float value) pure nothrow @nogc
{
    union FloatBits
    {
        float value;
        uint bits;
    }

    FloatBits raw = void;
    raw.value = value;
    return raw.bits;
}

private int floatToJavaInt(float value) pure nothrow @nogc
{
    if (value != value)
        return 0;
    if (value >= 2_147_483_648.0f)
        return int.max;
    if (value <= -2_147_483_648.0f)
        return int.min;
    return cast(int) value;
}

private int compareFloat(float left, float right) pure nothrow @nogc
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    if (left == right)
        return 0;
    return left != left ? (right != right ? 0 : 1) : -1;
}

// A byte view can share a D float array even at a non-4-byte origin. Follow the
// overlap direction and capture all four source bytes before storing any.
private void copyFloats(scope byte[] target, scope const(byte)[] source, bool swap) pure nothrow @nogc
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
    const count = target.length / float.sizeof;
    foreach (word; 0 .. count)
    {
        const offset = (reverse ? count - 1 - word : word) * float.sizeof;
        const b0 = source[offset];
        const b1 = source[offset + 1];
        const b2 = source[offset + 2];
        const b3 = source[offset + 3];
        if (swap)
        {
            target[offset] = b3;
            target[offset + 1] = b2;
            target[offset + 2] = b1;
            target[offset + 3] = b0;
        }
        else
        {
            target[offset] = b0;
            target[offset + 1] = b1;
            target[offset + 2] = b2;
            target[offset + 3] = b3;
        }
    }
}

private float[] allocateFloats(int capacity) pure nothrow
{
    auto floats = new float[capacity == 0 ? 1 : capacity];
    foreach (ref item; floats)
        item = 0.0f;
    return floats[0 .. capacity];
}
