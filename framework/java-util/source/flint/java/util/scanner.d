/*
 * Copyright (c) 1997, 2023, Oracle and/or its affiliates. All rights reserved.
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
 *
 * Modified by the Flint authors: scoped to the String source, default
 * whitespace delimiter and line reader. Ported from OpenJDK 21.0.13
 * src/java.base/share/classes/java/util/Scanner.java.
 */
/// Java SE 21 `Scanner` over an in-memory `String`.
///
/// The scoped port covers the `Scanner(String)` constructor, the default
/// `Character.isWhitespace` token delimiter, `hasNext`/`next`, the
/// `hasNextLine`/`nextLine` reader, `close` and `ioException`. Delimiter
/// patterns, `Readable` sources and the numeric `next*` methods are not yet
/// ported, so the leaf stays small and links only the whitespace predicate.
module flint.java.util.scanner;

import flint.java.lang : IllegalStateException, NullPointerException, UnsupportedOperationException;
import flint.java.lang.internal.characterwhitespace : isWhitespace;
import flint.java.util : Iterator, NoSuchElementException;

@safe:

/// A `Scanner` that splits a `String` at Java whitespace and reads lines.
final class Scanner : Iterator!string
{
    private string text;
    private size_t cursor;
    private bool closed;

    /// Scans `source`. A null source is rejected, an empty source is not.
    this(string source)
    {
        if (source.ptr is null)
            throw new NullPointerException();
        this.text = source;
    }

    /// Whether a token remains, skipping whitespace without consuming it.
    override bool hasNext()
    {
        ensureOpen();
        size_t index = cursor;
        while (index < text.length)
        {
            dchar codePoint;
            const step = codePointAt(text, index, codePoint);
            if (!isWhitespace(codePoint))
                return true;
            index += step;
        }
        return false;
    }

    /// The next whitespace-delimited token, or `NoSuchElementException`.
    override string next()
    {
        ensureOpen();
        skipWhitespace();
        if (cursor >= text.length)
            throw new NoSuchElementException();
        const start = cursor;
        while (cursor < text.length)
        {
            dchar codePoint;
            const step = codePointAt(text, cursor, codePoint);
            if (isWhitespace(codePoint))
                break;
            cursor += step;
        }
        return text[start .. cursor];
    }

    /// `Scanner` does not support removal.
    override void remove()
    {
        throw new UnsupportedOperationException();
    }

    /// Whether any character, including whitespace, remains on the current line.
    bool hasNextLine()
    {
        ensureOpen();
        return cursor < text.length;
    }

    /// The rest of the current line, including leading whitespace, and consumes
    /// its terminator (`\n`, `\r` or `\r\n`).
    string nextLine()
    {
        ensureOpen();
        if (cursor >= text.length)
            throw new NoSuchElementException();
        const start = cursor;
        while (cursor < text.length)
        {
            const c = text[cursor];
            if (c == '\n')
            {
                const end = cursor;
                cursor++;
                return text[start .. end];
            }
            if (c == '\r')
            {
                const end = cursor;
                cursor++;
                if (cursor < text.length && text[cursor] == '\n')
                    cursor++;
                return text[start .. end];
            }
            cursor++;
        }
        return text[start .. cursor];
    }

    /// Releases the source. Later scanning operations throw `IllegalStateException`.
    void close()
    {
        closed = true;
    }

    /// The last I/O error, which is always null for a `String` source.
    Throwable ioException() pure nothrow @nogc
    {
        return null;
    }

    private void ensureOpen()
    {
        if (closed)
            throw new IllegalStateException();
    }

    private void skipWhitespace()
    {
        while (cursor < text.length)
        {
            dchar codePoint;
            const step = codePointAt(text, cursor, codePoint);
            if (!isWhitespace(codePoint))
                return;
            cursor += step;
        }
    }
}

/// Decode one UTF-8 scalar at `index`, replacing an invalid sequence with one
/// U+FFFD byte so the cursor always advances.
private size_t codePointAt(string text, size_t index, out dchar codePoint) @safe pure nothrow @nogc
{
    const first = cast(ubyte) text[index];
    if (first < 0x80)
    {
        codePoint = first;
        return 1;
    }
    size_t length;
    dchar value;
    if ((first & 0xE0) == 0xC0)
    {
        length = 2;
        value = first & 0x1F;
    }
    else if ((first & 0xF0) == 0xE0)
    {
        length = 3;
        value = first & 0x0F;
    }
    else if ((first & 0xF8) == 0xF0)
    {
        length = 4;
        value = first & 0x07;
    }
    else
    {
        codePoint = 0xFFFD;
        return 1;
    }
    if (index + length > text.length)
    {
        codePoint = 0xFFFD;
        return 1;
    }
    foreach (offset; 1 .. length)
    {
        const next = cast(ubyte) text[index + offset];
        if ((next & 0xC0) != 0x80)
        {
            codePoint = 0xFFFD;
            return 1;
        }
        value = (value << 6) | (next & 0x3F);
    }
    codePoint = value;
    return length;
}
