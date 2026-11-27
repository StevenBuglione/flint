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
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : Comparable, IllegalArgumentException, IndexOutOfBoundsException,
    JavaObject, NullPointerException, UnsupportedOperationException;
import flint.java.nio.buffer : Buffer, arraySize, boundMessage, checkFromToIndex, checkIndex, checkRange;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.byteorder : ByteOrder;
import flint.java.nio.internal.buffercursor : BufferCursor;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;

@safe:

class CharBuffer : Buffer, Comparable!CharBuffer
{
    mixin JavaObject;

    private enum Storage : ubyte
    {
        words,
        bigEndian,
        littleEndian,
        text
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

    /// Wrap UTF-8 text as a read-only buffer of its UTF-16 code units, like Java's string-backed buffer: no
    /// accessible array, native order (R14, R26).
    static CharBuffer wrap(scope const(char)[] text) pure
    {
        return wrapText(text, 0, 0, true);
    }

    /// ditto, positioned at UTF-16 unit `start` with its limit at `end`; the capacity is the text's UTF-16 length.
    static CharBuffer wrap(scope const(char)[] text, int start, int end) pure
    {
        return wrapText(text, start, end, false);
    }

    private static CharBuffer wrapText(scope const(char)[] text, int start, int end, bool whole) pure
    {
        auto buffer = new CharBuffer(null, 0, BufferCursor(0, 0, 0), Storage.text | readOnlyFlag);
        const capacity = arraySize(buffer.scanOrWriteUtf16(text, size_t.max, size_t.max));
        if (whole)
            end = capacity;
        // Java's Buffer constructor rejects the bounds and wrap rethrows a bare IndexOutOfBoundsException.
        if (start < 0 || end < start || end > capacity)
            throw new IndexOutOfBoundsException;
        buffer.backing = cast(byte[]) allocateWords(capacity);
        buffer.scanOrWriteUtf16(text, 0, capacity);
        buffer.cursor = BufferCursor(capacity, start, end);
        return buffer;
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

    final int length() const pure nothrow @nogc
    {
        return remaining();
    }

    final bool isEmpty() const pure nothrow @nogc
    {
        return !hasRemaining();
    }

    final wchar charAt(int index) const pure
    {
        checkIndex(index, 1, remaining());
        return load(position() + index);
    }

    CharBuffer subSequence(int start, int end) pure
    {
        checkFromToIndex(start, end, remaining());
        const int offset = position();
        return new CharBuffer(backing, origin, BufferCursor(capacity(), offset + start, offset + end), storageFlags);
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

    CharBuffer put(scope CharBuffer source) pure
    {
        if (source is this)
        {
            checkWritableHeap();
            throw new IllegalArgumentException("The source buffer is this buffer");
        }
        checkWritable();
        requireBuffer(source);
        const length = source.cursor.remaining();
        if (length > remaining())
            throwOverflow();

        copyFromBuffer(position(), source, source.cursor.position(), length);
        advance(length);
        source.advance(length);
        return this;
    }

    CharBuffer put(int index, scope CharBuffer source, int offset, int length) pure
    {
        checkWritableHeap();
        checkRange(index, length, limit());
        requireBuffer(source);
        checkRange(offset, length, source.cursor.limit());
        checkWritable();
        copyFromBuffer(index, source, offset, length);
        return this;
    }

    /// Write UTF-16 code units from UTF-8 input using Java UTF-16 start/end bounds (R14, R26).
    CharBuffer put(scope const(char)[] source, int start, int end) pure
    {
        checkWritableHeap();
        return putUtf8Range(source, start, end, arraySize(scanOrWriteUtf16(source, size_t.max, size_t.max)));
    }

    /// Write all UTF-16 code units from UTF-8 input (R14, R26).
    final CharBuffer put(scope const(char)[] source) pure
    {
        checkWritableHeap();
        const total = arraySize(scanOrWriteUtf16(source, size_t.max, size_t.max));
        return putUtf8Range(source, 0, total, total);
    }

    /// Append one UTF-16 code unit by relative put.
    CharBuffer append(wchar value) pure
    {
        return put(value);
    }

    /// Append UTF-8 text as UTF-16 code units, as Java's `append(CharSequence)` puts `csq.toString()` (R14, R26).
    final CharBuffer append(scope const(char)[] text) pure
    {
        return put(text);
    }

    /// Append UTF-16 units `start` to `end` of UTF-8 text, as Java puts `csq.subSequence(start, end)`. A read-only
    /// heap buffer rejects first; the bounds are checked before the put's own checks (R14, R26).
    final CharBuffer append(scope const(char)[] text, int start, int end) pure
    {
        checkWritableHeap();
        checkFromToIndex(start, end, arraySize(scanOrWriteUtf16(text, size_t.max, size_t.max)));
        return put(text, start, end);
    }

    /// Transfer remaining characters to target. Java's signature declares IOException.
    int read(CharBuffer target) pure
    {
        const sourceLimit = limit();
        const sourcePosition = position();
        const available = sourceLimit - sourcePosition;
        if (available == 0)
            return -1;

        requireBuffer(target);
        const room = target.remaining();
        if (room == 0)
            return 0;

        const count = room < available ? room : available;
        if (count < available)
            limit(sourcePosition + count);
        scope (exit)
            limit(sourceLimit);
        target.put(this);
        return count;
    }

    CharBuffer compact() pure
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
        auto that = cast(CharBuffer) other;
        const length = cursor.remaining();
        return that !is null && length == that.cursor.remaining() && firstMismatch(that, length) < 0;
    }

    int hashCode() const pure nothrow @nogc
    {
        uint hash = 1;
        foreach_reverse (index; cursor.position() .. cursor.limit())
            hash = hash * 31 + load(index);
        return cast(int) hash;
    }

    override int compareTo(CharBuffer other) pure
    {
        requireBuffer(other);
        const left = cursor.remaining();
        const right = other.cursor.remaining();
        const index = firstMismatch(other, left < right ? left : right);
        if (index < 0)
            return left - right;
        return cast(int) load(cursor.position() + index) - cast(int) other.load(other.cursor.position() + index);
    }

    int mismatch(CharBuffer other) pure
    {
        requireBuffer(other);
        const left = cursor.remaining();
        const right = other.cursor.remaining();
        const common = left < right ? left : right;
        const index = firstMismatch(other, common);
        return index < 0 && left != right ? common : index;
    }

    /// Render the remaining UTF-16 units as UTF-8. Each lone surrogate becomes U+FFFD (R14).
    override string toString() pure nothrow
    {
        if (!hasRemaining())
            return "";
        return (cast(const CharBuffer) this).utf8Text();
    }

    private char[] utf8Text() const pure nothrow
    {
        const end = limit();
        size_t byteCount;
        for (int index = position(); index < end;)
            byteCount += utf8Width(nextScalar(index, end));

        auto output = new char[byteCount];
        size_t offset;
        for (int index = position(); index < end;)
        {
            const scalar = nextScalar(index, end);
            const width = utf8Width(scalar);
            writeUtf8(output[offset .. offset + width], scalar);
            offset += width;
        }
        return output;
    }

    private CharBuffer putUtf8Range(scope const(char)[] source, int start, int end, int total) pure
    {
        const count = cast(int)(cast(uint) end - cast(uint) start);
        checkRange(start, count, total);
        checkWritable();
        if (count > remaining())
            throwOverflow();
        if (count != 0)
            scanOrWriteUtf16(source, start, cast(size_t) start + count);
        advance(count);
        return this;
    }

    private size_t scanOrWriteUtf16(scope const(char)[] source, size_t firstUnit, size_t endUnit) pure nothrow @nogc
    {
        pragma(inline, false);
        int dest = position();
        size_t unit;
        for (size_t index = 0; index < source.length && unit < endUnit;)
        {
            const scalar = decodeUtf8(source, index);
            if (scalar <= 0xFFFF)
            {
                if (unit >= firstUnit)
                    store(dest++, cast(wchar) scalar);
                ++unit;
            }
            else
            {
                const adjusted = scalar - 0x10000;
                if (unit >= firstUnit)
                    store(dest++, cast(wchar)(0xD800 + (adjusted >> 10)));
                ++unit;
                if (unit >= firstUnit && unit < endUnit)
                    store(dest++, cast(wchar)(0xDC00 + (adjusted & 0x3FF)));
                ++unit;
            }
        }
        return unit;
    }

    private dchar nextScalar(ref int index, int end) const pure nothrow @nogc
    {
        const first = load(index++);
        if (first < 0xD800 || first > 0xDFFF)
            return first;
        if (first < 0xDC00 && index < end)
        {
            const second = load(index);
            if (second >= 0xDC00 && second <= 0xDFFF)
            {
                ++index;
                return cast(dchar)(0x10000 + ((first - 0xD800) << 10) + second - 0xDC00);
            }
        }
        return '\uFFFD';
    }

    private int firstMismatch(scope const(CharBuffer) other, int length) const scope pure nothrow @nogc
    {
        pragma(inline, false);
        const left = cursor.position();
        const right = other.cursor.position();
        foreach (index; 0 .. length)
            if (load(left + index) != other.load(right + index))
                return index;
        return -1;
    }

    private void copyFromBuffer(int index, scope CharBuffer source, int offset, int length) scope pure nothrow @nogc
    {
        pragma(inline, false);
        copyWords(memory(index, length), source.memory(offset, length), needsSwap() != source.needsSwap());
    }

    private byte[] memory(int index, int length) return scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * wchar.sizeof;
        return backing[start .. start + cast(size_t) length * wchar.sizeof];
    }

    private bool needsSwap() const scope pure nothrow @nogc
    {
        version (LittleEndian)
            return storageKind() == Storage.bigEndian;
        else
            return storageKind() == Storage.littleEndian;
    }

    private Storage storageKind() const scope pure nothrow @nogc
    {
        return cast(Storage)(storageFlags & ~readOnlyFlag);
    }

    private bool littleEndian() const scope pure nothrow @nogc
    {
        version (LittleEndian)
            return storageKind() != Storage.bigEndian;
        else
            return storageKind() == Storage.littleEndian;
    }

    private wchar load(int index) const scope pure nothrow @nogc
    {
        const start = cast(size_t)(origin + index) * wchar.sizeof;
        const first = cast(ubyte) backing[start];
        const second = cast(ubyte) backing[start + 1];
        return cast(wchar)(littleEndian() ? first | (second << 8) : (first << 8) | second);
    }

    private void store(int index, wchar value) pure nothrow @nogc
    {
        pragma(inline, false);
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

    pragma(inline, false) private void checkArray() const pure
    {
        if (storageKind() != Storage.words)
            throw new UnsupportedOperationException;
        checkWritable();
    }

    pragma(inline, false) private void checkWritableHeap() const pure
    {
        // HeapCharBufferR overrides both buffer puts and rejects before any validation.
        if (storageFlags == (Storage.words | readOnlyFlag))
            checkWritable();
    }

    pragma(inline, false) private void checkWritable() const pure
    {
        if ((storageFlags & readOnlyFlag) != 0)
            throw new ReadOnlyBufferException;
    }
}

private size_t utf8Width(dchar scalar) pure nothrow @nogc
{
    return 1 + (scalar > 0x7F) + (scalar > 0x7FF) + (scalar > 0xFFFF);
}

private void writeUtf8(scope char[] output, dchar scalar) pure nothrow @nogc
{
    // Fill continuation bytes from the low bits, then write the leading byte.
    static immutable ubyte[5] leadingBits = [0, 0, 0xC0, 0xE0, 0xF0];
    for (size_t index = output.length; index > 1;)
    {
        output[--index] = cast(char)(0x80 | (scalar & 0x3F));
        scalar >>= 6;
    }
    output[0] = cast(char)(leadingBits[output.length] | scalar);
}

private void requireBuffer(scope CharBuffer source) pure
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
