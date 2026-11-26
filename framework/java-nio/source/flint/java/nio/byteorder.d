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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/ByteOrder.java
 * Modified by the Flint authors.
 */
module flint.java.nio.byteorder;

@safe:

/// Byte ordering of multibyte values. The default value is BIG_ENDIAN.
struct ByteOrder
{
    /// Most significant byte first.
    static immutable ByteOrder BIG_ENDIAN = ByteOrder(false);

    /// Least significant byte first.
    static immutable ByteOrder LITTLE_ENDIAN = ByteOrder(true);

    private bool littleEndian;

    private this(bool littleEndian) pure nothrow @nogc
    {
        this.littleEndian = littleEndian;
    }

    /// The byte order of the compiling target.
    static ByteOrder nativeOrder() pure nothrow @nogc
    {
        version (LittleEndian)
            return LITTLE_ENDIAN;
        else
            return BIG_ENDIAN;
    }

    /// The name of this byte order.
    string toString() const pure nothrow @nogc
    {
        return littleEndian ? "LITTLE_ENDIAN" : "BIG_ENDIAN";
    }
}
