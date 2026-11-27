/*
 * Copyright (c) 1994, 2021, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/StringTokenizer.java
// Modified by the Flint authors.

module flint.java.util.stringtokenizer;

import core.exception : onOutOfMemoryError;
import flint.engine.aot.any : Any;
import flint.engine.aot.text : decodeUtf8;
import flint.java.util : NoSuchElementException;
import flint.java.util.enumeration : Enumeration;

@safe:

/**
 * Breaks a string into tokens separated by delimiter code points.
 *
 * Positions are UTF-8 offsets into the D string, and delimiters match whole
 * code points, which is what Java's UTF-16 scan selects for well-formed text.
 * A `null` string or delimiter set counts as empty (R26): Java throws
 * `NullPointerException`, eagerly for the string and at the next scan for the
 * delimiters.
 */
class StringTokenizer : Enumeration!Any
{
    private int currentPosition;
    private int newPosition = -1;
    private immutable int maxPosition;
    private immutable string str;
    private string delimiters;
    private immutable bool retDelims;
    private bool delimsChanged;
    private dchar maxDelimCodePoint;

    mixin Enumeration!Any.Defaults;

    /// Tokenizes `str` at the code points of `delim`, returning each delimiter as a token when `returnDelims` is set.
    this(string str, string delim, bool returnDelims)
    {
        this.str = str;
        maxPosition = javaLength(str.length);
        retDelims = returnDelims;
        setDelimiters(delim);
    }

    /// Tokenizes `str` at the code points of `delim`.
    this(string str, string delim)
    {
        this(str, delim, false);
    }

    /// Tokenizes `str` at space, tab, newline, carriage return and form feed.
    this(string str)
    {
        this(str, " \t\n\r\f", false);
    }

    /// Whether another token follows the current position.
    bool hasMoreTokens()
    {
        // Remember the skipped position so nextToken does not scan the delimiters again.
        newPosition = skipDelimiters(currentPosition);
        return newPosition < maxPosition;
    }

    /// The next token. Throws NoSuchElementException when no token remains.
    string nextToken()
    {
        currentPosition = newPosition >= 0 && !delimsChanged ? newPosition : skipDelimiters(currentPosition);
        delimsChanged = false;
        newPosition = -1;

        if (currentPosition >= maxPosition)
            throw new NoSuchElementException();
        const start = currentPosition;
        currentPosition = scanToken(currentPosition);
        return str[start .. currentPosition];
    }

    /// Replaces the delimiter set, which stays in effect afterwards, and returns the next token.
    string nextToken(string delim)
    {
        setDelimiters(delim);
        delimsChanged = true;
        return nextToken();
    }

    /// The same as hasMoreTokens.
    bool hasMoreElements()
    {
        return hasMoreTokens();
    }

    /// The next token as a Java Object (R23).
    Any nextElement()
    {
        return Any.of(nextToken());
    }

    /// The number of nextToken calls that would succeed with the current delimiters. The position does not change.
    int countTokens()
    {
        int count = 0;
        int position = currentPosition;
        while (position < maxPosition)
        {
            position = skipDelimiters(position);
            if (position >= maxPosition)
                break;
            position = scanToken(position);
            count++;
        }
        return count;
    }

    private void setDelimiters(string delim) pure nothrow @nogc
    {
        delimiters = delim;
        dchar m = 0;
        for (size_t i = 0; i < delim.length;)
        {
            const c = decodeUtf8(delim, i);
            if (m < c)
                m = c;
        }
        maxDelimCodePoint = m;
    }

    private int skipDelimiters(int startPos) const pure nothrow @nogc
    {
        size_t position = startPos;
        while (!retDelims && position < maxPosition)
        {
            size_t next = position;
            if (!isDelimiter(decodeUtf8(str, next)))
                break;
            position = next;
        }
        return cast(int) position;
    }

    private int scanToken(int startPos) const pure nothrow @nogc
    {
        size_t position = startPos;
        while (position < maxPosition)
        {
            size_t next = position;
            if (isDelimiter(decodeUtf8(str, next)))
                break;
            position = next;
        }
        if (retDelims && startPos == position)
        {
            size_t next = position;
            if (isDelimiter(decodeUtf8(str, next)))
                position = next;
        }
        return cast(int) position;
    }

    private bool isDelimiter(dchar c) const pure nothrow @nogc
    {
        if (c > maxDelimCodePoint)
            return false;
        for (size_t i = 0; i < delimiters.length;)
        {
            if (decodeUtf8(delimiters, i) == c)
                return true;
        }
        return false;
    }
}

private int javaLength(size_t length) pure nothrow @nogc
{
    // Java positions are int, so no Java string is longer.
    if (length > int.max)
        onOutOfMemoryError();
    return cast(int) length;
}
