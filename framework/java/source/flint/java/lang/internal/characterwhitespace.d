/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
/// Java 21 Character's whitespace predicate for a Unicode code point.
module flint.java.lang.internal.characterwhitespace;

@safe:

/// Excludes nonbreaking space, figure space and narrow nonbreaking space.
bool isWhitespace(dchar codePoint) pure nothrow @nogc
{
    if (codePoint <= 0x20)
        return (codePoint >= 0x09 && codePoint <= 0x0D) || codePoint >= 0x1C;
    if (codePoint >= 0x2000 && codePoint <= 0x200A)
        return codePoint != 0x2007;
    return codePoint == 0x1680 || codePoint == 0x2028 || codePoint == 0x2029 || codePoint == 0x205F
        || codePoint == 0x3000;
}

/// Classify one Java UTF-16 code unit.
bool isWhitespace(wchar codeUnit) pure nothrow @nogc
{
    return isWhitespace(cast(dchar) codeUnit);
}

/// Classify a signed Java code point, returning false outside the Unicode range.
bool isWhitespace(int codePoint) pure nothrow @nogc
{
    return isWhitespace(cast(dchar) codePoint);
}

/// Classify a code point held in an unsigned D integer.
bool isWhitespace(uint codePoint) pure nothrow @nogc
{
    return isWhitespace(cast(dchar) codePoint);
}
