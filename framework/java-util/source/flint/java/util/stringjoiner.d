/*
 * Copyright (c) 2013, 2021, Oracle and/or its affiliates. All rights reserved.
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
 * Modified by the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/StringJoiner.java
module flint.java.util.stringjoiner;

import core.exception : onOutOfMemoryError;

@safe:

/// Joins elements with a delimiter and optional surrounding text.
final class StringJoiner
{
    private immutable string delimiter;
    private immutable string prefix;
    private immutable string suffix;
    private string[] elements;
    private string emptyValue;

    private immutable size_t delimiterUnits;
    private size_t elementCount;
    private size_t contentBytes;
    private immutable int framingUnits;
    private int contentUnits;
    private int emptyUnits;

    /// Creates a joiner without prefix or suffix.
    this(string delimiter)
    {
        this(delimiter, "", "");
    }

    /// Creates a joiner with the supplied delimiter, prefix and suffix.
    this(string delimiter, string prefix, string suffix)
    {
        this.delimiter = delimiter;
        this.prefix = prefix;
        this.suffix = suffix;
        delimiterUnits = utf16Length(delimiter);
        framingUnits = javaLength(checkedAdd(utf16Length(prefix), utf16Length(suffix)));
    }

    /// Replaces the output used before the first element is added.
    StringJoiner setEmptyValue(string value)
    {
        const units = javaLength(utf16Length(value));
        emptyValue = value.length == 0 ? "" : value;
        emptyUnits = units;
        return this;
    }

    /// Appends one element. A null element adds the literal `"null"`.
    StringJoiner add(string element)
    {
        if (element is null)
            element = "null";
        return append(element, utf16Length(element));
    }

    /// Appends a snapshot of the other joiner's nonempty contents as one element.
    StringJoiner merge(StringJoiner other)
    {
        if (other is null)
            failNull();
        if (other.elementCount == 0)
            return this;
        return append(other.render("", ""), other.contentUnits);
    }

    /// Length of the joined string in Java UTF-16 code units.
    int length() const pure nothrow @nogc
    {
        return elementCount == 0 && emptyValue !is null ? emptyUnits : framingUnits + contentUnits;
    }

    /// Renders the current contents, with the configured framing.
    override string toString() const
    {
        if (elementCount == 0 && emptyValue !is null)
            return emptyValue;
        return render(prefix, suffix);
    }

    private StringJoiner append(string element, size_t units)
    {
        size_t bytes = checkedAdd(contentBytes, element.length);
        size_t nextUnits = checkedAdd(contentUnits, units);
        if (elementCount != 0)
        {
            bytes = checkedAdd(bytes, delimiter.length);
            nextUnits = checkedAdd(nextUnits, delimiterUnits);
        }
        // Validate the content and framing before expanding storage or changing any counters.
        const totalUnits = javaLength(checkedAdd(nextUnits, framingUnits));

        if (elementCount == elements.length)
        {
            const capacity = elementCount == 0 ? 8 : checkedAdd(elementCount, elementCount);
            auto expanded = new string[capacity];
            expanded[0 .. elementCount] = elements[];
            elements = expanded;
        }
        elements[elementCount++] = element;
        contentBytes = bytes;
        contentUnits = totalUnits - framingUnits;
        return this;
    }

    private string render(string before, string after) const
    {
        const size = checkedAdd(checkedAdd(contentBytes, before.length), after.length);
        if (size == 0)
            return "";
        if (elementCount == 1 && before.length == 0 && after.length == 0)
            return elements[0];

        return join(elements[0 .. elementCount], delimiter, before, after, size);
    }
}

private int javaLength(size_t units) pure nothrow @nogc
{
    if (units > int.max)
        onOutOfMemoryError();
    return cast(int) units;
}

private char[] join(scope const(string)[] items, string delimiter, string before, string after, size_t size) pure
{
    auto text = new char[size];
    size_t position;
    copyPart(text, position, before);
    foreach (index, element; items)
    {
        if (index != 0)
            copyPart(text, position, delimiter);
        copyPart(text, position, element);
    }
    copyPart(text, position, after);
    return text;
}

private void copyPart(scope char[] text, ref size_t position, string part) pure nothrow @nogc
{
    text[position .. position + part.length] = part;
    position += part.length;
}

private size_t checkedAdd(size_t left, size_t right) pure nothrow @nogc
{
    if (right > size_t.max - left)
        onOutOfMemoryError();
    return left + right;
}

private size_t utf16Length(scope const(char)[] text) pure nothrow @nogc
{
    size_t units;
    foreach (octet; text)
        if ((octet & 0xc0) != 0x80)
            units += octet >= 0xf0 ? 2 : 1;
    return units;
}

pragma(inline, false) private noreturn failNull()
{
    import flint.java.lang : NullPointerException;

    throw new NullPointerException();
}
