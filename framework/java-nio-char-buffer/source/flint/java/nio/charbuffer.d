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
 * Includes the corresponding HeapCharBuffer behavior.
 * Modified by the Flint authors.
 */
/** Java NIO buffers backed by D arrays of UTF-16 code units. */
module flint.java.nio.charbuffer;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException;
import flint.java.nio.buffer : Buffer, arraySize, boundMessage, checkIndex, checkRange;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.internal.buffercursor : BufferCursor;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;

@safe:

class CharBuffer : Buffer
{
    private wchar[] backing;
    private int origin;
    private bool readOnly;

    private this(wchar[] backing, int origin, BufferCursor cursor, bool readOnly) pure nothrow @nogc
    {
        super(cursor);
        this.backing = backing;
        this.origin = origin;
        this.readOnly = readOnly;
    }

    static CharBuffer allocate(int capacity) pure
    {
        if (capacity < 0)
            throw new IllegalArgumentException(boundMessage("capacity", capacity, "0", 0));
        return new CharBuffer(allocateWords(capacity), 0, BufferCursor(capacity, 0, capacity), false);
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
        return new CharBuffer(words, 0, BufferCursor(capacity, offset, offset + length), false);
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
        return readOnly;
    }

    override bool isDirect() const pure nothrow @nogc
    {
        return false;
    }

    final override bool hasArray() const pure nothrow @nogc
    {
        return !readOnly;
    }

    final wchar[] array() pure
    {
        checkWritable();
        return backing;
    }

    protected override Any erasedArray()
    {
        return Any.of(array());
    }

    final override int arrayOffset() const pure
    {
        checkWritable();
        return origin;
    }

    ByteOrder order() const pure nothrow @nogc
    {
        return ByteOrder.nativeOrder();
    }

    override CharBuffer slice() pure
    {
        return slice(position(), remaining());
    }

    override CharBuffer slice(int index, int length) pure
    {
        checkRange(index, length, limit());
        return new CharBuffer(backing, origin + index, BufferCursor(length, 0, length), readOnly);
    }

    override CharBuffer duplicate() pure
    {
        return new CharBuffer(backing, origin, cursor, readOnly);
    }

    CharBuffer asReadOnlyBuffer() pure
    {
        return new CharBuffer(backing, origin, cursor, true);
    }

    wchar get() pure
    {
        if (!hasRemaining())
            throw new BufferUnderflowException;
        const value = backing[origin + position()];
        advance(1);
        return value;
    }

    wchar get(int index) const pure
    {
        checkIndex(index, 1, limit());
        return backing[origin + index];
    }

    CharBuffer put(wchar value) pure
    {
        checkWritable();
        if (!hasRemaining())
            throw new BufferOverflowException;
        backing[origin + position()] = value;
        advance(1);
        return this;
    }

    CharBuffer put(int index, wchar value) pure
    {
        checkWritable();
        checkIndex(index, 1, limit());
        backing[origin + index] = value;
        return this;
    }

    private void checkWritable() const pure
    {
        if (readOnly)
            throw new ReadOnlyBufferException;
    }
}

private wchar[] allocateWords(int capacity) pure nothrow
{
    // Java char storage starts at zero, while D wchar arrays default to wchar.init.
    auto words = cast(wchar[]) new ushort[capacity == 0 ? 1 : capacity];
    return words[0 .. capacity];
}
