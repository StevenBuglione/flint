/*
 * Copyright (c) 2014, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/zip/CRC32C.java
// Modified by the Flint authors.

module flint.java.util.zip.data.crc32c;

@safe:

package(flint.java.util.zip) immutable uint[256] byteTable = generateByteTable();

private uint[256] generateByteTable() pure nothrow @nogc
{
    // Reflected form of the Castagnoli polynomial 0x1EDC6F41.
    enum uint reversedPolynomial = 0x82F63B78;
    uint[256] table;
    foreach (uint index; 0 .. table.length)
    {
        uint remainder = index;
        foreach (bit; 0 .. 8)
        {
            const bool set = (remainder & 1) != 0;
            remainder >>= 1;
            if (set)
                remainder ^= reversedPolynomial;
        }
        table[index] = remainder;
    }
    return table;
}
