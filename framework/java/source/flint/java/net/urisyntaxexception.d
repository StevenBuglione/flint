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

/* Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/URISyntaxException.java
 * Modified by the Flint authors.
 */

module flint.java.net.urisyntaxexception;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

/++
Checked exception thrown to indicate that a string could not be parsed as a URI reference.

Java's `Exception` is D's `Exception` (deviation D-8): the checked/unchecked distinction is compile-time only.
+/
class URISyntaxException : Exception
{
    private string input_;
    private int index_;

    /// Java's `URISyntaxException(String input, String reason, int index)`.
    this(string input, string reason, int index) pure
    {
        super(reason);
        if (input is null || reason is null)
            throw new NullPointerException();
        if (index < -1)
            throw new IllegalArgumentException();
        input_ = input;
        index_ = index;
    }

    /// Java's `URISyntaxException(String input, String reason)`, with an unknown error index.
    this(string input, string reason) pure
    {
        this(input, reason, -1);
    }

    /// The input string.
    string getInput() const pure nothrow @nogc
    {
        return input_;
    }

    /// The reason the input could not be parsed.
    string getReason() const pure nothrow @nogc
    {
        return msg;
    }

    /// The error index, or -1 when unknown.
    int getIndex() const pure nothrow @nogc
    {
        return index_;
    }

    /// Java's synthesized message: the reason, then ` at index N` when known, then `: input`.
    string getMessage() const pure
    {
        if (index_ <= -1)
            return msg ~ ": " ~ input_;
        return msg ~ " at index " ~ decimal(cast(ulong) index_) ~ ": " ~ input_;
    }
}
