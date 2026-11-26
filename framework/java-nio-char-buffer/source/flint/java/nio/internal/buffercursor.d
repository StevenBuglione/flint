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
/** Allocation-free position, limit and mark transitions for Java NIO buffer views. */
module flint.java.nio.internal.buffercursor;

@safe:

package(flint.java.nio) struct BufferCursor
{
    private int extent;
    private int offset;
    private int end;
    private int checkpoint = -1;

    this(int capacity, int position, int limit) pure nothrow @nogc
    {
        assert(0 <= position && position <= limit && limit <= capacity);
        extent = capacity;
        offset = position;
        end = limit;
    }

    int capacity() const pure nothrow @nogc
    {
        return extent;
    }

    int position() const pure nothrow @nogc
    {
        return offset;
    }

    int limit() const pure nothrow @nogc
    {
        return end;
    }

    int remaining() const pure nothrow @nogc
    {
        return end - offset;
    }

    void advance(int count) pure nothrow @nogc
    {
        assert(count >= 0 && count <= remaining());
        offset += count;
    }

    bool setPosition(int position) pure nothrow @nogc
    {
        if (position < 0 || position > end)
            return false;
        offset = position;
        if (checkpoint > position)
            checkpoint = -1;
        return true;
    }

    bool setLimit(int limit) pure nothrow @nogc
    {
        if (limit < 0 || limit > extent)
            return false;
        end = limit;
        if (offset > limit)
            offset = limit;
        if (checkpoint > limit)
            checkpoint = -1;
        return true;
    }

    void mark() pure nothrow @nogc
    {
        checkpoint = offset;
    }

    bool reset() pure nothrow @nogc
    {
        if (checkpoint < 0)
            return false;
        offset = checkpoint;
        return true;
    }

    void clear() pure nothrow @nogc
    {
        end = extent;
        rewind();
    }

    void flip() pure nothrow @nogc
    {
        end = offset;
        rewind();
    }

    void rewind() pure nothrow @nogc
    {
        offset = 0;
        checkpoint = -1;
    }
}
