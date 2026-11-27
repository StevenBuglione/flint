/*
 * Copyright (c) 1994, 2021, Oracle and/or its affiliates. All rights reserved.
 *
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
 *
 */

/*
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/ArrayIndexOutOfBoundsException.java
 * Modified by the Flint authors.
 */
module flint.java.lang.arrayindexoutofboundsexception;

import flint.java.lang : IndexOutOfBoundsException, decimal;

@safe:

/++
Thrown when an array is accessed at an index outside its bounds.

Java's implicit array access throws this with the JVM's own detail, `Index N out of bounds for length M`.
`forArrayIndex` builds that detail for a port that checks the bound explicitly; the constructors keep the
message Java's public API produces.
+/
class ArrayIndexOutOfBoundsException : IndexOutOfBoundsException
{
    /// No detail message.
    this() pure nothrow
    {
        super();
    }

    /// `message`, and optionally a `cause`.
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    /// Java's `ArrayIndexOutOfBoundsException(int index)`: "Array index out of range: " and the index.
    this(int index, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Array index out of range: " ~ decimal(index), null, file, line);
    }

    /++
    The JVM's detail for an implicit array access that is out of bounds: `Index N out of bounds for length M`.
    A port that checks an array bound explicitly uses this where Java's own array access would throw.
    +/
    static ArrayIndexOutOfBoundsException forArrayIndex(int index, int length,
            string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        return new ArrayIndexOutOfBoundsException(
                "Index " ~ decimal(index) ~ " out of bounds for length " ~ decimal(length), null, file, line);
    }
}
