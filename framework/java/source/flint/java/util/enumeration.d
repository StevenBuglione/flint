/*
 * Copyright (c) 1994, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/Enumeration.java
// Modified by the Flint authors.

module flint.java.util.enumeration;

import flint.java.util.internal.iterator : Iterator;

@safe:

/// A sequence of elements consumed one at a time.
interface Enumeration(E)
{
    /// Whether at least one element remains.
    bool hasMoreElements();

    /// The next element. Throws NoSuchElementException at exhaustion.
    E nextElement();

    /// An iterator over the remaining elements. Using the enumeration directly afterwards is undefined.
    Iterator!E asIterator();

    /// R3 implementation of the Java default method.
    mixin template Defaults(alias Result = Iterator!E, alias Adapter = EnumerationIterator!E)
    {
        Result asIterator()
        {
            return new Adapter(this);
        }
    }
}

private final class EnumerationIterator(E) : Iterator!E
{
    private Enumeration!E remaining;

    this(Enumeration!E remaining)
    {
        this.remaining = remaining;
    }

    bool hasNext()
    {
        return remaining.hasMoreElements();
    }

    E next()
    {
        return remaining.nextElement();
    }

    void remove()
    {
        import flint.java.lang : UnsupportedOperationException;

        throw new UnsupportedOperationException("remove");
    }
}
