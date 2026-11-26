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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/Buffer.java
 * Modified by the Flint authors.
 */
/** Java NIO buffer position, mark, limit and array contracts. */
module flint.java.nio.buffer;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, UnsupportedOperationException;
import flint.java.nio.internal.buffercursor : BufferCursor;
import flint.java.nio.invalidmarkexception : InvalidMarkException;

@safe:

abstract class Buffer
{
    package(flint.java.nio) BufferCursor cursor;

    package(flint.java.nio) this(BufferCursor cursor) pure nothrow @nogc
    {
        this.cursor = cursor;
    }

    final int capacity() const pure nothrow @nogc
    {
        return cursor.capacity();
    }

    final int position() const pure nothrow @nogc
    {
        return cursor.position();
    }

    Buffer position(int position) pure
    {
        if (!cursor.setPosition(position))
            throw new IllegalArgumentException(boundMessage("newPosition", position, "limit", limit()));
        return this;
    }

    final int limit() const pure nothrow @nogc
    {
        return cursor.limit();
    }

    Buffer limit(int limit) pure
    {
        if (!cursor.setLimit(limit))
            throw new IllegalArgumentException(boundMessage("newLimit", limit, "capacity", capacity()));
        return this;
    }

    Buffer mark() pure nothrow @nogc
    {
        cursor.mark();
        return this;
    }

    Buffer reset() pure
    {
        if (!cursor.reset())
            throw new InvalidMarkException;
        return this;
    }

    Buffer clear() pure nothrow @nogc
    {
        cursor.clear();
        return this;
    }

    Buffer flip() pure nothrow @nogc
    {
        cursor.flip();
        return this;
    }

    Buffer rewind() pure nothrow @nogc
    {
        cursor.rewind();
        return this;
    }

    final int remaining() const pure nothrow @nogc
    {
        return cursor.remaining();
    }

    final bool hasRemaining() const pure nothrow @nogc
    {
        return remaining() != 0;
    }

    abstract bool isReadOnly() const pure nothrow @nogc;
    abstract bool hasArray() const pure nothrow @nogc;

    /// Expose the backing array with its original element type and shared storage.
    Any array()()
    {
        return erasedArray();
    }

    protected Any erasedArray()
    {
        throw new UnsupportedOperationException;
    }

    abstract int arrayOffset() const pure;
    abstract bool isDirect() const pure nothrow @nogc;
    abstract Buffer slice() pure;
    abstract Buffer slice(int index, int length) pure;
    abstract Buffer duplicate() pure;

    protected final string summary(scope string name) const pure nothrow
    {
        enum nameCapacity = 48;
        enum fields = "[pos= lim= cap=";
        char[nameCapacity + fields.length + 31] text;
        assert(name.length <= nameCapacity);
        text[0 .. name.length] = name[];
        size_t length = name.length;
        appendField(text[], length, "[pos=", position());
        appendField(text[], length, " lim=", limit());
        appendField(text[], length, " cap=", capacity());
        text[length++] = ']';
        return text[0 .. length].idup;
    }

    protected final void advance(int count) scope pure nothrow @nogc
    {
        cursor.advance(count);
    }
}

package(flint.java.nio) int arraySize(size_t length) pure
{
    if (length > int.max)
        throwArrayTooLarge();
    return cast(int) length;
}

pragma(inline, false) private noreturn throwArrayTooLarge() pure
{
    throw new IllegalArgumentException("Array exceeds Java buffer capacity");
}

package(flint.java.nio) void checkRange(int index, int count, int limit) pure
{
    if ((index | count | limit) < 0 || count > limit - index)
        throwRangeError(index, count, limit);
}

pragma(inline, false) private noreturn throwRangeError(int index, int count, int limit) pure
{
    char[96] text;
    size_t used;
    appendField(text[], used, "Range [", index);
    appendField(text[], used, ", ", index);
    appendField(text[], used, " + ", count);
    appendField(text[], used, ") out of bounds for length ", limit);
    throw new IndexOutOfBoundsException(text[0 .. used].idup);
}

package(flint.java.nio) void checkFromToIndex(int start, int end, int limit) pure
{
    if (start < 0 || end < start || end > limit)
        throwFromToIndexError(start, end, limit);
}

pragma(inline, false) private noreturn throwFromToIndexError(int start, int end, int limit) pure
{
    char[96] text;
    size_t used;
    appendField(text[], used, "Range [", start);
    appendField(text[], used, ", ", end);
    appendField(text[], used, ") out of bounds for length ", limit);
    throw new IndexOutOfBoundsException(text[0 .. used].idup);
}

package(flint.java.nio) void checkIndex(int index, int width, int limit) pure
{
    if (index < 0 || index > limit - width)
        throwIndexError();
}

pragma(inline, false) private noreturn throwIndexError() pure
{
    throw new IndexOutOfBoundsException;
}

package(flint.java.nio) string boundMessage(scope string name, int value, scope string upper, int bound) pure nothrow
{
    char[72] text;
    size_t used;
    appendText(text[], used, name);
    const comparison = value < 0 ? " < " : " > ";
    appendText(text[], used, comparison);
    appendText(text[], used, value < 0 ? "0" : upper);
    appendField(text[], used, ": (", value);
    appendField(text[], used, comparison, value < 0 ? 0 : bound);
    appendText(text[], used, ")");
    return text[0 .. used].idup;
}

private void appendText(scope char[] output, ref size_t length, scope const(char)[] text) pure nothrow @nogc
{
    output[length .. length + text.length] = text[];
    length += text.length;
}

private void appendField(scope char[] output, ref size_t length, scope string label, int value) pure nothrow @nogc
{
    char[11] digits;
    size_t start = digits.length;
    const negative = value < 0;
    uint magnitude = negative ? 0u - cast(uint) value : cast(uint) value;
    do
    {
        digits[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude != 0);
    if (negative)
        digits[--start] = '-';

    appendText(output, length, label);
    appendText(output, length, digits[start .. $]);
}
