/*
 * Copyright (c) 2007, 2021, Oracle and/or its affiliates. All rights reserved.
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
// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/file/InvalidPathException.java
// Modified by the Flint authors.
module flint.java.nio.file.invalidpathexception;

import flint.java.lang : IllegalArgumentException, Integer;

@safe:

/// Thrown when a path string cannot be converted to a path.
/// Null input and reason strings count as empty under R26.
class InvalidPathException : IllegalArgumentException
{
    private const string input;
    private const string reason;
    private const int index;

    /// Constructs a failure with the original input, reason and error index.
    /// Throws IllegalArgumentException for an index below -1.
    this(string input, string reason, int index)
    {
        super(formatMessage(input, reason, index));
        this.input = input.length ? input : "";
        this.reason = reason.length ? reason : "";
        this.index = index;
    }

    /// Constructs a failure with an unknown error index (-1).
    this(string input, string reason)
    {
        this(input, reason, -1);
    }

    /// Returns the original path string.
    string getInput() const pure nothrow @nogc
    {
        return input;
    }

    /// Returns the reason the path was rejected.
    string getReason() const pure nothrow @nogc
    {
        return reason;
    }

    /// Returns the supplied error index, or -1 if it was unknown.
    int getIndex() const pure nothrow @nogc
    {
        return index;
    }

    /// Returns the detail message formatted at construction (D-JDK-3).
    override string getMessage() const pure nothrow @nogc
    {
        return super.getMessage();
    }

    private static string formatMessage(string input, string reason, int index)
    {
        if (index < -1)
            throw new IllegalArgumentException;
        if (index == -1)
            return reason ~ ": " ~ input;
        return reason ~ " at index " ~ Integer.toString(index) ~ ": " ~ input;
    }
}
