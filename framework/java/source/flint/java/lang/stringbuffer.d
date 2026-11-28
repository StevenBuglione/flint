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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/StringBuffer.java and
// src/java.base/share/classes/jdk/internal/.../AbstractStringBuilder.java (append, length, toString).
// Modified by the Flint authors: the UTF-16 store is one internal engine shared with the coming
// java.lang.StringBuilder; Java's synchronized methods are D's synchronized blocks; the checked
// char[] range overload and the Appendable/CharSequence conformance wait on the exception-leaf split.
module flint.java.lang.stringbuffer;

import flint.java.lang.internal.abstractstringbuilder : AbstractStringBuilder;

@safe:

/++
Java's `StringBuffer`: a mutable UTF-16 text buffer. Every append returns the original buffer, and operations are
synchronized on the buffer, as Java's are.

This is the first slice: the constructors, `append(String)`, `append(char)`, `length` and `toString` that
`java.text.Format` needs. The `char[]` range overload and the `Appendable`/`CharSequence` conformance follow once
the exception leaves (#3) make `IndexOutOfBoundsException` importable without the `java.lang` aggregate.
+/
final class StringBuffer
{
    private AbstractStringBuilder text;

    /// An empty buffer.
    this()
    {
        text = new AbstractStringBuilder;
    }

    /// A buffer holding `str`. Java rejects null; Flint starts empty, as R26 maps absent text to empty.
    this(string str)
    {
        text = new AbstractStringBuilder;
        if (str !is null)
            text.appendText(str);
    }

    /// The length in UTF-16 code units, as Java counts them (R14).
    int length() const
    {
        synchronized (this)
            return text.length();
    }

    /// A synchronized UTF-8 snapshot of the text. A lone surrogate becomes U+FFFD (R14).
    override string toString() const
    {
        synchronized (this)
            return text.snapshot();
    }

    /// Append `str`; a null string appends the text `"null"`, as Java does.
    StringBuffer append(string str)
    {
        synchronized (this)
        {
            if (str is null)
                text.appendText("null");
            else
                text.appendText(str);
            return this;
        }
    }

    /// Append one Java `char`, i.e. one UTF-16 code unit, including an unpaired surrogate (R14).
    StringBuffer append(wchar unit)
    {
        synchronized (this)
        {
            text.appendUnit(unit);
            return this;
        }
    }
}
