/*
 * Copyright (c) 2001, 2023, Oracle and/or its affiliates. All rights reserved.
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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/charset/CoderResult.java
 * Modified by the Flint authors.
 */
module flint.java.nio.charset.coderresult;

import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;

@safe:

/// A description of the result state of a charset coder. The default value is UNDERFLOW.
struct CoderResult
{
    private enum ubyte kindUnderflow = 0;
    private enum ubyte kindOverflow = 1;
    private enum ubyte kindMalformed = 2;
    private enum ubyte kindUnmappable = 3;

    /// Result indicating that the input buffer has been consumed or more input is required.
    static immutable CoderResult UNDERFLOW = CoderResult(kindUnderflow, 0);

    /// Result indicating that there is insufficient room remaining in the output buffer.
    static immutable CoderResult OVERFLOW = CoderResult(kindOverflow, 0);

    private ubyte kind;
    private int errorLength;

    private this(ubyte kind, int errorLength) pure nothrow @nogc
    {
        this.kind = kind;
        this.errorLength = errorLength;
    }

    /// A descriptive string matching Java's `UNDERFLOW`, `OVERFLOW`, `MALFORMED[n]`, or `UNMAPPABLE[n]`.
    string toString() const pure nothrow
    {
        if (kind == kindUnderflow)
            return "UNDERFLOW";
        if (kind == kindOverflow)
            return "OVERFLOW";
        return formatError(kind == kindMalformed ? "MALFORMED" : "UNMAPPABLE", errorLength);
    }

    /// True if this result denotes underflow.
    bool isUnderflow() const pure nothrow @nogc
    {
        return kind == kindUnderflow;
    }

    /// True if this result denotes overflow.
    bool isOverflow() const pure nothrow @nogc
    {
        return kind == kindOverflow;
    }

    /// True if this result denotes either a malformed-input or unmappable-character error.
    bool isError() const pure nothrow @nogc
    {
        return kind >= kindMalformed;
    }

    /// True if this result denotes a malformed-input error.
    bool isMalformed() const pure nothrow @nogc
    {
        return kind == kindMalformed;
    }

    /// True if this result denotes an unmappable-character error.
    bool isUnmappable() const pure nothrow @nogc
    {
        return kind == kindUnmappable;
    }

    /// The length of the erroneous input. Throws `UnsupportedOperationException` when not an error.
    int length() const pure
    {
        if (!isError())
            throwUnsupported();
        return errorLength;
    }

    /// Returns the result describing a malformed-input error of the given positive `length`.
    static CoderResult malformedForLength(int length) pure
    {
        return errorForLength(kindMalformed, length);
    }

    /// Returns the result describing an unmappable-character error of the given positive `length`.
    static CoderResult unmappableForLength(int length) pure
    {
        return errorForLength(kindUnmappable, length);
    }

    private static CoderResult errorForLength(ubyte kind, int length) pure
    {
        if (length <= 0)
            throwNonPositiveLength();
        return CoderResult(kind, length);
    }
}

private char[] formatError(string prefix, int value) pure nothrow
{
    pragma(inline, false);
    char[10] digits = void;
    size_t start = digits.length;
    uint remaining = cast(uint) value;
    do
    {
        digits[--start] = cast(char)('0' + remaining % 10);
        remaining /= 10;
    }
    while (remaining != 0);

    const digitCount = digits.length - start;
    auto result = new char[prefix.length + 1 + digitCount + 1];
    result[0 .. prefix.length] = prefix[];
    result[prefix.length] = '[';
    result[prefix.length + 1 .. prefix.length + 1 + digitCount] = digits[start .. $];
    result[$ - 1] = ']';
    return result;
}

pragma(inline, false) private noreturn throwNonPositiveLength() pure
{
    throw new IllegalArgumentException("Non-positive length");
}

pragma(inline, false) private noreturn throwUnsupported() pure
{
    throw new UnsupportedOperationException;
}
