// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/System.java
/*
 * Copyright (c) 1994, 2023, Oracle and/or its affiliates. All rights reserved.
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
// Modified by the Flint authors: use the target platform's line separator and Flint's wall and monotonic clocks.
module flint.java.lang.system;

import flint.engine.aot.clock : monoNanos = nanoTime, wallMillis = currentTimeMillis;

@safe:

/// Process-wide system facilities.
struct System
{
    /// Read the wall clock in signed milliseconds since the Unix epoch.
    alias currentTimeMillis = wallMillis;

    /// Read the monotonic clock in nanoseconds from an arbitrary origin. Only differences between reads are meaningful.
    alias nanoTime = monoNanos;

    /// The target platform's initial line separator, independent of later property changes.
    static string lineSeparator() pure nothrow @nogc
    {
        version (Windows)
            return "\r\n";
        else
            return "\n";
    }
}
