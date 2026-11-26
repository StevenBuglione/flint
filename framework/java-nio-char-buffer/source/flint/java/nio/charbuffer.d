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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/CharBuffer.java
 * Includes HeapCharBuffer and heap ByteBufferAsCharBuffer view behavior.
 * Modified by the Flint authors.
 */
/** Java NIO UTF-16 code units in a character array or a view of heap bytes. */
module flint.java.nio.charbuffer;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, UnsupportedOperationException;
import flint.java.nio.buffer : Buffer, arraySize, boundMessage, checkIndex, checkRange;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.internal.buffercursor : BufferCursor;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;

@safe:

class CharBuffer : Buffer
{
    private enum Storage : ubyte
    {
        words,
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

    package(flint.java.nio) static CharBuffer ofBytes(byte[] bytes, bool littleEndian, bool readOnly) pure
    {
        const capacity = arraySize(bytes.length / wchar.sizeof);
        const kind = littleEndian ? Storage.littleEndian : Storage.bigEndian;
        const flags = cast(ubyte)(kind | (readOnly ? readOnlyFlag : 0));
        return new CharBuffer(bytes, 0, BufferCursor(capacity, 0, capacity), flags);
    }

    static CharBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new CharBuffer(cast(byte[]) allocateWords(capacity), 0, BufferCursor(capacity, 0,
                capacity), Storage.words);
    }

    static CharBuffer wrap(wchar[] words) pure
    {
        return wrap(words, 0, arraySize(words.length));
    }

    static CharBuffer wrap(wchar[] words, int offset, int length) pure
    {
        const capacity = arraySize(words.length);
        if ((offset | length) < 0 || length > capacity - offset)
            throw new IndexOutOfBoundsException;
        if (words is null)
            words = allocateWords(0);
        return new CharBuffer(cast(byte[]) words, 0, BufferCursor(capacity, offset, offset + length), Storage.words);
    }

    alias position = Buffer.position;
    alias limit = Buffer.limit;

    override CharBuffer position(int position) pure
    {
        super.position(position);
        return this;
    }

    override CharBuffer limit(int limit) pure
    {
        super.limit(limit);
        return this;
    }

    override CharBuffer mark() pure nothrow @nogc
    {
        super.mark();
        return this;
    }

    override CharBuffer reset() pure
    {
        super.reset();
        return this;
    }

    override CharBuffer clear() pure nothrow @nogc
    {
        super.clear();
        return this;
    }

    override CharBuffer flip() pure nothrow @nogc
    {
        super.flip();
        return this;
    }

    override CharBuffer rewind() pure nothrow @nogc
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
        return storageFlags == Storage.words;
    }

    final wchar[] array() pure
    {
        checkArray();
        return cast(wchar[]) backing;
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

    override CharBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override CharBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new CharBuffer(backing, origin + index, BufferCursor(length, 0, length), storageFlags);
    }

    override CharBuffer duplicate() pure
    {
        return new CharBuffer(backing, origin, cursor, storageFlags);
    }

    CharBuffer asReadOnlyBuffer() pure
    {
        return new CharBuffer(backing, origin, cursor, cast(ubyte)(storageFlags | readOnlyFlag));
    }

    wchar get() pure
    {
        if (!hasRemaining())
            throwUnderflow();
        const value = load(position());
        advance(1);
        return value;
    }

    CharBuffer get(scope wchar[] target, int offset, int length) pure
    {
        checkRange(offset, length, arraySize(target.length));
        if (length > remaining())
            throwUnderflow();
        copyWords(cast(byte[]) target[offset .. offset + length], memory(position(), length), needsSwap());
        advance(length);
        return this;
    }

    CharBuffer get(scope wchar[] target) pure
    {
        return get(target, 0, arraySize(target.length));
    }

    CharBuffer get(int index, scope wchar[] target, int offset, int length) pure
    {
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(target.length));
        copyWords(cast(byte[]) target[offset .. offset + length], memory(index, length), needsSwap());
        return this;
    }

    CharBuffer get(int index, scope wchar[] target) pure
    {
        return get(index, target, 0, arraySize(target.length));
    }

    wchar get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return load(index);
    }

    CharBuffer put(wchar value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throwOverflow();
        store(position(), value);
        advance(1);
        return this;
    }

    CharBuffer put(int index, wchar value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        store(index, value);
        return this;
    }

    CharBuffer put(scope const(wchar)[] source, int offset, int length) pure
    {
        checkWritable();
        checkRange(offset, length, arraySize(source.length));
        if (length > remaining())
            throwOverflow();
        copyWords(memory(position(), length), cast(const(byte)[]) source[offset .. offset + length], needsSwap());
        advance(length);
        return this;
    }

    final CharBuffer put(scope const(wchar)[] source) pure
    {
        return put(source, 0, arraySize(source.length));
    }

    CharBuffer put(int index, scope const(wchar)[] source, int offset, int length) pure
    {
        checkWritable();
        checkRange(index, length, limit());
        checkRange(offset, length, arraySize(source.length));
        copyWords(memory(index, length), cast(const(byte)[]) source[offset .. offset + length], needsSwap());
        return this;
    }

    CharBuffer put(int index, scope const(wchar)[] source) pure
    {
        return put(index, source, 0, arraySize(source.length));
    }

    private byte[] memory(int index, int length) pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * wchar.sizeof;
        return backing[start .. start + cast(size_t) length * wchar.sizeof];
    }

    private bool needsSwap() const pure nothrow @nogc
    {
        version (LittleEndian)
            return storageKind() == Storage.bigEndian;
        else
            return storageKind() == Storage.littleEndian;
    }

    private Storage storageKind() const pure nothrow @nogc
    {
        return cast(Storage)(storageFlags & ~readOnlyFlag);
    }

    private bool littleEndian() const pure nothrow @nogc
    {
        version (LittleEndian)
            return storageKind() != Storage.bigEndian;
        else
            return storageKind() == Storage.littleEndian;
    }

    private wchar load(int index) const pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * wchar.sizeof;
        const first = cast(ubyte) backing[start];
        const second = cast(ubyte) backing[start + 1];
        return cast(wchar)(littleEndian() ? first | (second << 8) : (first << 8) | second);
    }

    private void store(int index, wchar value) pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * wchar.sizeof;
        const high = cast(byte)(value >> 8);
        const low = cast(byte) value;
        if (littleEndian())
        {
            backing[start] = low;
            backing[start + 1] = high;
        }
        else
        {
            backing[start] = high;
            backing[start + 1] = low;
        }
    }

    private void checkArray() const pure
    {
        if (storageKind() != Storage.words)
            throw new UnsupportedOperationException;
        checkWritable();
    }

    pragma(inline, false) private void checkWritable() const pure
    {
        if ((storageFlags & readOnlyFlag) != 0)
            throw new ReadOnlyBufferException;
    }
}

pragma(inline, false) private noreturn throwUnderflow() pure
{
    throw new BufferUnderflowException;
}

pragma(inline, false) private noreturn throwOverflow() pure
{
    throw new BufferOverflowException;
}

// A byte view can share a D word array even at an odd origin. Follow the
// overlap direction and capture both source bytes before storing either.
private void copyWords(scope byte[] target, scope const(byte)[] source, bool swap) pure nothrow @nogc
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
    const count = target.length / wchar.sizeof;
    const size_t orderBit = swap;
    foreach (word; 0 .. count)
    {
        const offset = (reverse ? count - 1 - word : word) * wchar.sizeof;
        const first = source[offset ^ orderBit];
        const second = source[(offset + 1) ^ orderBit];
        target[offset] = first;
        target[offset + 1] = second;
    }
}

private wchar[] allocateWords(int capacity) pure nothrow
{
    // Java char storage starts at zero, while D wchar arrays default to wchar.init.
    auto words = cast(wchar[]) new ushort[capacity == 0 ? 1 : capacity];
    return words[0 .. capacity];
}
