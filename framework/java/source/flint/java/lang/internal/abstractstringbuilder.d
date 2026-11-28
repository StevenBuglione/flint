/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

/// The mutable UTF-16 text store shared by `StringBuffer` and, later, `StringBuilder`.
module flint.java.lang.internal.abstractstringbuilder;

@safe:

/++
Java's `AbstractStringBuilder` storage, shared by `StringBuffer` and, later, `StringBuilder`. Java stores UTF-16
code units (or Latin-1); Flint always stores UTF-16, so `length` counts Java's units and a lone surrogate survives
until `snapshot` encodes it as U+FFFD (R14).

The units are kept as little-endian bytes in a `char[]` rather than a `wchar[]`. The store is a class, not a struct
embedded in the public buffer: both choices keep the buffer's `RTInfo` from naming a layout the linker resolves to
`flint.java.character`, whose module records would then pull Java's time, text and SQL modules into every buffer
probe (the inherited `flint.java.lang` closure debt).
+/
package(flint) final class AbstractStringBuilder
{
    private char[] bytes;

    /// Append the UTF-8 text `text`. The caller handles Java's `null` before calling.
    void appendText(scope const(char)[] text)
    {
        size_t i;
        while (i < text.length)
        {
            const decoded = decodeUtf8(text, i);
            appendCodePoint(decoded.codePoint);
            i += decoded.width;
        }
    }

    private static struct Decoded
    {
        uint codePoint;
        size_t width;
    }

    private static Decoded decodeUtf8(scope const(char)[] text, size_t i)
    {
        const uint first = cast(ubyte) text[i];
        if (first < 0x80)
            return Decoded(first, 1);
        if ((first & 0xE0) == 0xC0)
            return decodeTwo(text, i, first);
        if ((first & 0xF0) == 0xE0)
            return decodeThree(text, i, first);
        if ((first & 0xF8) == 0xF0)
            return decodeFour(text, i, first);
        return Decoded(0xFFFD, 1);
    }

    private static bool continuation(scope const(char)[] text, size_t i) pure nothrow @nogc
    {
        return i < text.length && (text[i] & 0xC0) == 0x80;
    }

    private static Decoded decodeTwo(scope const(char)[] text, size_t i, uint first) pure nothrow @nogc
    {
        if (continuation(text, i + 1))
        {
            const uint value = ((first & 0x1F) << 6) | (text[i + 1] & 0x3F);
            if (value >= 0x80)
                return Decoded(value, 2);
        }
        return Decoded(0xFFFD, 1);
    }

    private static Decoded decodeThree(scope const(char)[] text, size_t i, uint first) pure nothrow @nogc
    {
        if (continuation(text, i + 1) && continuation(text, i + 2))
        {
            const uint value = ((first & 0x0F) << 12) | ((text[i + 1] & 0x3F) << 6) | (text[i + 2] & 0x3F);
            if (value >= 0x800 && !(value >= 0xD800 && value <= 0xDFFF))
                return Decoded(value, 3);
        }
        return Decoded(0xFFFD, 1);
    }

    private static Decoded decodeFour(scope const(char)[] text, size_t i, uint first) pure nothrow @nogc
    {
        if (continuation(text, i + 1) && continuation(text, i + 2) && continuation(text, i + 3))
        {
            const uint value = ((first & 0x07) << 18) | ((text[i + 1] & 0x3F) << 12) | (
                    (text[i + 2] & 0x3F) << 6) | (text[i + 3] & 0x3F);
            if (value >= 0x10000 && value <= 0x10FFFF)
                return Decoded(value, 4);
        }
        return Decoded(0xFFFD, 1);
    }

    /// Append one Java `char`, including an unpaired surrogate.
    void appendUnit(wchar unit)
    {
        putUnit(unit);
    }

    /// Append a supplementary code point as Java's surrogate pair.
    void appendCodePoint(uint codePoint)
    {
        if (codePoint < 0x10000)
            putUnit(codePoint);
        else
        {
            const uint value = codePoint - 0x10000;
            putUnit(0xD800 + (value >> 10));
            putUnit(0xDC00 + (value & 0x3FF));
        }
    }

    /// The length in UTF-16 code units.
    int length() const pure nothrow @nogc
    {
        return cast(int)(bytes.length >> 1);
    }

    /// A UTF-8 snapshot: a lone surrogate becomes U+FFFD (R14).
    string snapshot() const
    {
        char[] encoded;
        encoded.reserve(bytes.length + (bytes.length >> 1) + 1);
        size_t i;
        const size_t count = bytes.length >> 1;
        while (i < count)
        {
            const uint unit = unitAt(i);
            if (unit < 0x80)
            {
                encoded ~= cast(char) unit;
                ++i;
                continue;
            }
            if (unit < 0x800)
            {
                encoded ~= cast(char)(0xC0 | (unit >> 6));
                encoded ~= cast(char)(0x80 | (unit & 0x3F));
                ++i;
                continue;
            }
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < count && unitAt(i + 1) >= 0xDC00 && unitAt(i + 1) <= 0xDFFF)
            {
                const uint codePoint = 0x10000 + ((unit - 0xD800) << 10) + (unitAt(i + 1) - 0xDC00);
                encoded ~= cast(char)(0xF0 | (codePoint >> 18));
                encoded ~= cast(char)(0x80 | ((codePoint >> 12) & 0x3F));
                encoded ~= cast(char)(0x80 | ((codePoint >> 6) & 0x3F));
                encoded ~= cast(char)(0x80 | (codePoint & 0x3F));
                i += 2;
                continue;
            }
            if (unit >= 0xD800 && unit <= 0xDFFF)
            {
                encoded ~= "\uFFFD";
                ++i;
                continue;
            }
            encoded ~= cast(char)(0xE0 | (unit >> 12));
            encoded ~= cast(char)(0x80 | ((unit >> 6) & 0x3F));
            encoded ~= cast(char)(0x80 | (unit & 0x3F));
            ++i;
        }
        return encoded.idup;
    }

    private void putUnit(uint unit)
    {
        bytes ~= cast(char)(unit & 0xFF);
        bytes ~= cast(char)((unit >> 8) & 0xFF);
    }

    private uint unitAt(size_t index) const pure nothrow @nogc
    {
        return cast(ubyte) bytes[index << 1] | (cast(uint)(cast(ubyte) bytes[(index << 1) + 1]) << 8);
    }
}
