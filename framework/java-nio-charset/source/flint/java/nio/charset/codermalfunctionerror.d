/*
 * Copyright (c) 2001, 2019, Oracle and/or its affiliates. All rights reserved.
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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/charset/CoderMalfunctionError.java
 * Modified by the Flint authors.
 */
module flint.java.nio.charset.codermalfunctionerror;

import flint.java.lang : IllegalStateException, javaToString;

@safe:

/++
Error thrown when the `decodeLoop` method of a `CharsetDecoder`, or the `encodeLoop` method of a `CharsetEncoder`,
throws an unexpected exception.

Java's `Error` maps to the catchable D `Exception` base (rule R8), as `AssertionError` does, because D's `Error`
skips cleanup. It is not a `RuntimeException`, so `catch (RuntimeException)` does not catch it, as in Java.
+/
class CoderMalfunctionError : Exception
{
    private Exception cause_;

    /// Initializes an instance with the unexpected exception that was thrown. The message is `cause.toString()`,
    /// or null for a null cause.
    this(Exception cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(cause is null ? null : javaToString(cause), file, line);
        cause_ = cause;
    }

    /// The detail message; null when there is none.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }

    /// `getMessage()`.
    string getLocalizedMessage() const pure nothrow @nogc
    {
        return getMessage();
    }

    /// The unexpected exception; null when it was null.
    inout(Exception) getCause() inout pure nothrow @nogc
    {
        return cause_;
    }

    /// The constructor always sets the cause, so Java's `initCause` always throws `IllegalStateException`.
    CoderMalfunctionError initCause(Throwable cause)
    {
        const detail = cause is null ? "a null" : javaToString(cause);
        throw new IllegalStateException("Can't overwrite cause with " ~ detail);
    }

    /// Java's `Throwable.toString()`: the class name, then `: message` when there is one.
    override string toString() const
    {
        return javaToString(this);
    }
}
