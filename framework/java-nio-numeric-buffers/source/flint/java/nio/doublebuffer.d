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
 * Includes HeapDoubleBuffer and heap ByteBufferAsDoubleBuffer view behavior.
 * Modified by the Flint authors.
 */
/** Java NIO IEEE 754 64-bit doubles in a double array or a view of heap bytes. */
module flint.java.nio.doublebuffer;

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

class DoubleBuffer : Buffer, Comparable!DoubleBuffer
{
    mixin JavaObject;

    private enum Storage : ubyte
    {
        doubles,
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

    package(flint.java.nio) static DoubleBuffer ofBytes(byte[] bytes, bool littleEndian, bool readOnly) pure
    {
        const capacity = arraySize(bytes.length / double.sizeof);
        const kind = littleEndian ? Storage.littleEndian : Storage.bigEndian;
        const flags = cast(ubyte)(kind | (readOnly ? readOnlyFlag : 0));
        return new DoubleBuffer(bytes, 0, BufferCursor(capacity, 0, capacity), flags);
    }

    static DoubleBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new DoubleBuffer(cast(byte[]) allocateDoubles(capacity), 0, BufferCursor(capacity, 0,
                capacity), Storage.doubles);
    }

    static DoubleBuffer wrap(double[] array) pure
    {
        return wrap(array, 0, arraySize(array.length));
    }

    static DoubleBuffer wrap(double[] array, int offset, int length) pure
    {
        const capacity = arraySize(array.length);
        if ((offset | length) < 0 || length > capacity - offset)
            throw new IndexOutOfBoundsException;
        if (array is null)
            array = allocateDoubles(0);
        return new DoubleBuffer(cast(byte[]) array, 0, BufferCursor(capacity, offset,
                offset + length), Storage.doubles);
    }

    alias position = Buffer.position;
    alias limit = Buffer.limit;

    override DoubleBuffer position(int position) pure
    {
        super.position(position);
        return this;
    }

    override DoubleBuffer limit(int limit) pure
    {
        super.limit(limit);
        return this;
    }

    override DoubleBuffer mark() pure nothrow @nogc
    {
        super.mark();
        return this;
    }

    override DoubleBuffer reset() pure
    {
        super.reset();
        return this;
    }

    override DoubleBuffer clear() pure nothrow @nogc
    {
        super.clear();
        return this;
    }

    override DoubleBuffer flip() pure nothrow @nogc
    {
        super.flip();
        return this;
    }

    override DoubleBuffer rewind() pure nothrow @nogc
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
        return storageFlags == Storage.doubles;
    }

    final double[] array() pure
    {
        checkArray();
        return cast(double[]) backing;
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

    override DoubleBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override DoubleBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new DoubleBuffer(backing, origin + index, BufferCursor(length, 0, length), storageFlags);
    }

    override DoubleBuffer duplicate() pure
    {
        return new DoubleBuffer(backing, origin, cursor, storageFlags);
    }

    DoubleBuffer asReadOnlyBuffer() pure
    {
        return new DoubleBuffer(backing, origin, cursor, cast(ubyte)(storageFlags | readOnlyFlag));
    }

    double get() pure
    {
        if (!hasRemaining())
            throwUnderflow();
        const value = load(position());
        advance(1);
        return value;
    }

    DoubleBuffer get(scope double[] dst, int offset, int length) pure
    {
        checkRange(offset, length, arraySize(dst.length));
        if (length > remaining())
            throwUnderflow();
        copyDoubles(cast(byte[]) dst[offset .. offset + length], memory(position(), length), needsSwap());
        advance(length);
        return this;
    }

    DoubleBuffer get(scope double[] dst) pure
    {
        return get(dst, 0, arraySize(dst.length));
    }

    DoubleBuffer get(int index, scope double[] dst, int offset, int length) pure
    {
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(dst.length));
        copyDoubles(cast(byte[]) dst[offset .. offset + length], memory(index, length), needsSwap());
        return this;
    }

    DoubleBuffer get(int index, scope double[] dst) pure
    {
        return get(index, dst, 0, arraySize(dst.length));
    }

    double get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return load(index);
    }

    DoubleBuffer put(double value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throwOverflow();
        store(position(), value);
        advance(1);
        return this;
    }

    DoubleBuffer put(int index, double value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        store(index, value);
        return this;
    }

    DoubleBuffer put(scope const(double)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(offset, length, arraySize(src.length));
        if (length > remaining())
            throwOverflow();
        copyDoubles(memory(position(), length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        advance(length);
        return this;
    }

    final DoubleBuffer put(scope const(double)[] src) pure
    {
        return put(src, 0, arraySize(src.length));
    }

    DoubleBuffer put(int index, scope const(double)[] src, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(src.length));
        copyDoubles(memory(index, length), cast(const(byte)[]) src[offset .. offset + length], needsSwap());
        return this;
    }

    DoubleBuffer put(int index, scope const(double)[] src) pure
    {
        return put(index, src, 0, arraySize(src.length));
    }

    DoubleBuffer put(scope DoubleBuffer src) pure
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

    DoubleBuffer put(int index, scope DoubleBuffer src, int offset, int length) pure
    {
        checkWritableHeap();
        checkRange(index, length, limit());
        requireBuffer(src);
        checkRange(offset, length, src.cursor.limit());
        checkWritable();
        copyFromBuffer(index, src, offset, length);
        return this;
    }

    DoubleBuffer compact() pure
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
        auto that = cast(DoubleBuffer) other;
        const length = cursor.remaining();
        return that !is null && length == that.cursor.remaining() && firstMismatch(that, length) < 0;
    }

    int hashCode() const pure nothrow @nogc
    {
        uint hash = 1;
        foreach_reverse (index; cursor.position() .. cursor.limit())
            hash = hash * 31 + cast(uint) doubleToJavaInt(load(index));
        return cast(int) hash;
    }

    override int compareTo(DoubleBuffer other) pure
    {
        requireBuffer(other);
        const left = cursor.remaining();
        const right = other.cursor.remaining();
        const index = firstMismatch(other, left < right ? left : right);
        if (index < 0)
            return left - right;
        return compareDouble(load(cursor.position() + index), other.load(other.cursor.position() + index));
    }

    int mismatch(DoubleBuffer other) pure
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
        case Storage.doubles:
            return "java.nio.HeapDoubleBuffer";
        case Storage.doubles | readOnlyFlag:
            return "java.nio.HeapDoubleBufferR";
        case Storage.bigEndian:
            return "java.nio.ByteBufferAsDoubleBufferB";
        case Storage.bigEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsDoubleBufferRB";
        case Storage.littleEndian:
            return "java.nio.ByteBufferAsDoubleBufferL";
        case Storage.littleEndian | readOnlyFlag:
            return "java.nio.ByteBufferAsDoubleBufferRL";
        }
    }

    private int firstMismatch(scope const DoubleBuffer other, int length) const scope pure nothrow @nogc
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
        if (kind == Storage.doubles)
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
        const start = cast(size_t)(origin + index) * double.sizeof;
        return backing[start .. start + cast(size_t) length * double.sizeof];
    }

    private void copyFromBuffer(int index, scope DoubleBuffer source, int offset, int length) pure nothrow @nogc
    {
        copyDoubles(memory(index, length), source.memory(offset, length), littleEndian() != source.littleEndian());
    }

    private double load(int index) const scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * double.sizeof;
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
        return bitsToDouble(bits);
    }

    private void store(int index, double value) pure nothrow @nogc
    {
        pragma(inline, false);
        const start = cast(size_t)(origin + index) * double.sizeof;
        const bits = doubleToBits(value);
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
        if (storageKind() != Storage.doubles)
            throw new UnsupportedOperationException;
        checkWritable();
    }

    pragma(inline, false) private void checkWritableHeap() const pure
    {
        if (storageFlags == (Storage.doubles | readOnlyFlag))
            checkWritable();
    }

    pragma(inline, false) private void checkWritable() const pure
    {
        if ((storageFlags & readOnlyFlag) != 0)
            throw new ReadOnlyBufferException;
    }
}

private void requireBuffer(scope DoubleBuffer source) pure
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

private double bitsToDouble(ulong bits) pure nothrow @nogc
{
    union DoubleBits
    {
        ulong bits;
        double value;
    }

    DoubleBits raw = void;
    raw.bits = bits;
    return raw.value;
}

private ulong doubleToBits(double value) pure nothrow @nogc
{
    union DoubleBits
    {
        double value;
        ulong bits;
    }

    DoubleBits raw = void;
    raw.value = value;
    return raw.bits;
}

private int doubleToJavaInt(double value) pure nothrow @nogc
{
    if (value != value)
        return 0;
    if (value >= cast(double) int.max)
        return int.max;
    if (value <= cast(double) int.min)
        return int.min;
    return cast(int) value;
}

private int compareDouble(double left, double right) pure nothrow @nogc
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    if (left == right)
        return 0;
    return left != left ? (right != right ? 0 : 1) : -1;
}

// A byte view can share a D double array even at a non-8-byte origin. Follow the
// overlap direction and capture all eight source bytes before storing any.
private void copyDoubles(scope byte[] target, scope const(byte)[] source, bool swap) pure nothrow @nogc
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
    const count = target.length / double.sizeof;
    foreach (word; 0 .. count)
    {
        const offset = (reverse ? count - 1 - word : word) * double.sizeof;
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

private double[] allocateDoubles(int capacity) pure nothrow
{
    auto doubles = new double[capacity == 0 ? 1 : capacity];
    foreach (ref item; doubles)
        item = 0.0;
    return doubles[0 .. capacity];
}
