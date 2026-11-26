// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/*
 * Copyright (c) 2003, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
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
 * Ported from openjdk 21.0.13: test/jdk/java/nio/Buffer/BasicChar.java and Basic.java
 * Modified by the Flint authors.
 */
module char_bulk_array_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import std.exception : assertThrown, collectException;

@safe:

private enum capacity = 64;
private enum offset = 7;
private enum absoluteLength = capacity - 2 * offset;

private wchar[capacity + offset] bulkSource()
{
    wchar[capacity + offset] source;
    foreach (i; 0 .. capacity)
    {
        const letter = i % 54;
        source[i + offset] = cast(wchar)('a' + letter + (letter > 26 ? 128 : 0));
    }
    return source;
}

@("BasicChar.bulkGet")
unittest
{
    auto source = bulkSource();
    wchar[capacity + offset] target;
    auto buffer = CharBuffer.wrap(source[offset .. $].dup);
    assert(buffer.get(target[], offset, capacity) is buffer);
    assert(buffer.position() == capacity && target[offset .. $] == source[offset .. $]);
}

@("BasicChar.absBulkGet")
unittest
{
    auto source = bulkSource();
    wchar[capacity + offset] target = 0;
    auto buffer = CharBuffer.wrap(source[].dup).limit(capacity - offset).position(42).mark();
    assert(buffer.get(offset, target[], offset, absoluteLength) is buffer);
    assert(buffer.position() == 42 && buffer.reset().position() == 42);
    assert(target[offset .. offset + absoluteLength] == source[offset .. offset + absoluteLength]);
    assert(target[offset - 1] == 0 && target[offset + absoluteLength] == 0);
}

@("BasicChar.bulkPutArray")
unittest
{
    const source = bulkSource();
    auto buffer = CharBuffer.allocate(capacity);
    assert(buffer.put(source[], offset, capacity) is buffer);
    assert(buffer.position() == capacity && buffer.array() == source[offset .. $]);
}

@("BasicChar.absBulkPutArray")
unittest
{
    const source = bulkSource();
    auto buffer = CharBuffer.allocate(capacity).limit(capacity - offset).position(42).mark();
    assert(buffer.put(offset, source[], offset, absoluteLength) is buffer);
    assert(buffer.position() == 42 && buffer.reset().position() == 42);
    assert(buffer.array()[offset .. capacity - offset] == source[offset .. capacity - offset]);
    assert(buffer.array()[offset - 1] == 0 && buffer.array()[capacity - offset] == 0);
}

@("Heap character bulk copies preserve both directions of live array overlap")
unittest
{
    wchar[] backing = [1, 2, 3, 4, 5];
    auto buffer = CharBuffer.wrap(backing).position(1).mark();
    assert(buffer.put(backing[0 .. 3]) is buffer);
    assert(backing == [1, 1, 2, 3, 5] && buffer.position() == 4);
    assert(buffer.reset().get(backing[0 .. 3]) is buffer);
    assert(backing == [1, 2, 3, 3, 5] && buffer.reset().position() == 1);

    auto slice = buffer.slice(1, 3).position(1).mark();
    assert(slice.asReadOnlyBuffer().get(0, backing[2 .. 5]).position() == 1);
    assert(backing == [1, 2, 2, 3, 3]);
    assert(slice.put(0, backing[0 .. 3]) is slice);
    assert(backing == [1, 1, 2, 2, 3]);
    assert(slice.reset().position() == 1);
}

@("Character bulk failures preserve storage and marks, and null slices act empty")
unittest
{
    wchar[] backing = [1, 2, 3, 4];
    wchar[4] target = [7, 7, 7, 7];
    auto buffer = CharBuffer.wrap(backing).limit(3).position(2).mark();

    auto relative = collectException!IndexOutOfBoundsException(buffer.get(target[], 4, 2));
    assert(relative.getMessage() == "Range [4, 4 + 2) out of bounds for length 4");
    assertThrown!BufferUnderflowException(buffer.get(target[], 0, 2));
    auto absolute = collectException!IndexOutOfBoundsException(buffer.get(2, target[], 4, 2));
    assert(absolute.getMessage() == "Range [2, 2 + 2) out of bounds for length 3");
    relative = collectException!IndexOutOfBoundsException(buffer.put(target[], 4, 2));
    assert(relative.getMessage() == "Range [4, 4 + 2) out of bounds for length 4");
    assertThrown!BufferOverflowException(buffer.put(target[], 0, 2));
    absolute = collectException!IndexOutOfBoundsException(buffer.put(2, target[], 4, 2));
    assert(absolute.getMessage() == "Range [2, 2 + 2) out of bounds for length 3");
    assert(target[] == [7, 7, 7, 7] && backing == [1, 2, 3, 4]);
    assert(buffer.position() == 2 && buffer.reset().position() == 2);

    auto readOnly = buffer.asReadOnlyBuffer();
    assertThrown!ReadOnlyBufferException(readOnly.put(target[], -1, 9));
    assertThrown!ReadOnlyBufferException(readOnly.put(-1, target[], -1, 9));
    assertThrown!ReadOnlyBufferException(readOnly.put(cast(const(wchar)[]) null));
    assert(readOnly.get(target[0 .. 1]) is readOnly && target[0] == 3);

    assert(buffer.get(cast(wchar[]) null) is buffer);
    assert(buffer.put(cast(const(wchar)[]) null) is buffer);
    assert(buffer.get(3, cast(wchar[]) null) is buffer);
    assert(buffer.put(3, cast(const(wchar)[]) null) is buffer);
    assertThrown!IndexOutOfBoundsException(buffer.get(4, cast(wchar[]) null));
    assertThrown!IndexOutOfBoundsException(buffer.put(cast(const(wchar)[]) null, 1, 0));
    assert(buffer.position() == 2 && buffer.reset().position() == 2);
}

@("BasicChar.bulkPutBuffer")
unittest
{
    auto source = bulkSource();
    auto from = CharBuffer.wrap(source[offset .. $].dup).asReadOnlyBuffer();
    auto into = CharBuffer.allocate(capacity);
    assert(into.put(from) is into);
    assert(into.position() == capacity && from.position() == capacity);
    assert(into.flip().array() == source[offset .. $]);
}
