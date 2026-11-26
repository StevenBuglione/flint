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

module flint.java.util.zip.crc32c;

import flint.java.util.zip.checksum : Checksum;
import flint.java.util.zip.data.crc32c : byteTable;

@safe:

/// A running CRC-32C checksum.
final class CRC32C : Checksum
{
    private uint crc = uint.max;

    this() pure nothrow @nogc
    {
    }

    override void update(int value) nothrow @nogc
    {
        crc = (crc >> 8) ^ byteTable[(crc ^ cast(ubyte) value) & 0xff];
    }

    override long getValue() nothrow @nogc
    {
        return ~crc;
    }

    override void reset() nothrow @nogc
    {
        crc = uint.max;
    }
}
