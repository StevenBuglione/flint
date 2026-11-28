/*
 * Copyright (c) 1995, 2020, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/SocketException.java
// Modified by the Flint authors.

/** Thrown to indicate that there is an error creating or accessing a Socket. */
module flint.java.net.socketexception;

import flint.java.io : IOException;
import flint.java.lang : javaToString;

@safe:

/// Thrown to indicate that there is an error creating or accessing a Socket.
class SocketException : IOException
{
    /// Constructs a `SocketException` with an optional detail message and cause.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message.length == 0 ? null : message, cause, file, line);
    }

    /// Constructs a `SocketException` whose detail message is `cause.toString()`.
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(cause is null ? null : javaToString(cause), cause, file, line);
    }
}
