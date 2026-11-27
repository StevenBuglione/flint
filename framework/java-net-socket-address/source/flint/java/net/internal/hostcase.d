/*
 * Copyright (c) 2003, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13:
//   src/java.base/share/classes/java/lang/StringUTF16.java (compareToCIImpl, toLowerCaseEx)
//   src/java.base/share/classes/java/lang/ConditionalSpecialCasing.java (isFinalCased, isCased)
//   src/java.base/share/classes/sun/text/resources/BreakIteratorRules.java (WordBreakRules, a subset)
// Modified by the Flint authors.

/++
The two `String` case operations `InetSocketAddress` applies to an unresolved host name: `equalsIgnoreCase`, and
`toLowerCase(Locale.ROOT).hashCode()` computed without building the lowered string.
+/
module flint.java.net.internal.hostcase;

import flint.engine.aot.text : decodeUtf8;
import flint.java.character : isLetter, isLowercaseLetter, isNumber, isUppercaseLetter, toLowerCase, toUpperCase;

@safe:

package(flint.java.net):

/// Java's `a.equalsIgnoreCase(b)`: code points pair up, and each pair is equal, equal after `toUpperCase`, or
/// equal after `toLowerCase` of those.
bool equalsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    size_t i, j;
    while (i < a.length && j < b.length)
    {
        const c1 = decodeUtf8(a, i);
        const c2 = decodeUtf8(b, j);
        if (c1 == c2)
            continue;
        const u1 = toUpperCase(c1);
        const u2 = toUpperCase(c2);
        if (u1 != u2 && toLowerCase(u1) != toLowerCase(u2))
            return false;
    }
    return i == a.length && j == b.length;
}

/++
Java's `s.toLowerCase(Locale.ROOT).hashCode()`. U+0130 lowers to `i` and U+0307, and a capital sigma lowers to
final `ς` when a cased letter precedes it in its word and none follows it there; every other code point takes
`Character.toLowerCase`.
+/
int lowerRootHashCode(scope const(char)[] s) pure nothrow @nogc
{
    int h;
    size_t i;
    while (i < s.length)
    {
        const start = i;
        const c = decodeUtf8(s, i);
        if (c == 0x0130)
            h = hashUtf16(hashUtf16(h, 'i'), 0x0307);
        else if (c == 0x03A3)
            h = hashUtf16(h, isFinalCased(s, start, i) ? 0x03C2 : 0x03C3);
        else
            h = hashUtf16(h, toLowerCase(c));
    }
    return h;
}

// String.hashCode's step for one code point, as one or two UTF-16 code units.
private int hashUtf16(int h, dchar c) pure nothrow @nogc
{
    if (c < 0x10000)
        return 31 * h + cast(int) c;
    h = 31 * h + cast(int)(0xD800 + ((c - 0x10000) >> 10));
    return 31 * h + cast(int)(0xDC00 + ((c - 0x10000) & 0x3FF));
}

// The sigma at s[start .. end] is preceded by a cased letter in its word, and no cased letter follows it there.
private bool isFinalCased(scope const(char)[] s, size_t start, size_t end) pure nothrow @nogc
{
    for (size_t i = start; !isBoundary(s, i);)
    {
        if (isCased(before(s, i)))
        {
            for (size_t k = end; !isBoundary(s, k);)
                if (isCased(decodeUtf8(s, k)))
                    return false;
            return true;
        }
    }
    return false;
}

// ConditionalSpecialCasing.isCased: Lu, Ll, Lt, or one of its Other_Lowercase and Other_Uppercase ranges.
private bool isCased(dchar c) pure nothrow @nogc
{
    return isUppercaseLetter(c) || isLowercaseLetter(c) || isTitlecaseLetter(c) || (c >= 0x02B0
            && c <= 0x02B8) || (c >= 0x02C0 && c <= 0x02C1) || (c >= 0x02E0 && c <= 0x02E4)
        || c == 0x0345 || c == 0x037A || (c >= 0x1D2C && c <= 0x1D61) || (c >= 0x2160 && c <= 0x217F)
        || (c >= 0x24B6 && c <= 0x24E9);
}

// The Lt category (Unicode 15).
private bool isTitlecaseLetter(dchar c) pure nothrow @nogc
{
    return c == 0x01C5 || c == 0x01C8 || c == 0x01CB || c == 0x01F2 || (c >= 0x1F88 && c <= 0x1F8F)
        || (c >= 0x1F98 && c <= 0x1F9F) || (c >= 0x1FA8 && c <= 0x1FAF) || c == 0x1FBC || c == 0x1FCC || c == 0x1FFC;
}

private enum Kind
{
    other,
    letter,
    digit,
    mark,
}

// The JDK word-rule class of a code point: letters (L), digits (N), and the combining diacritical marks U+0300 to
// U+036F, which attach to what precedes them.
private Kind kind(dchar c) pure nothrow @nogc
{
    if (isLetter(c))
        return Kind.letter;
    if (isNumber(c))
        return Kind.digit;
    if (c >= 0x0300 && c <= 0x036F)
        return Kind.mark;
    return Kind.other;
}

// <mid-word>: dashes, the connector `_`, soft hyphen, U+2027, quotes and the period, between two letters.
private bool isMidWord(dchar c) pure nothrow @nogc
{
    return c == '-' || c == '_' || c == 0x00AD || (c >= 0x2010 && c <= 0x2015) || c == 0x2027
        || c == '"' || c == '\'' || c == '.';
}

// <mid-num>: quotes, the period, the comma and U+066B, between two digits.
private bool isMidNum(dchar c) pure nothrow @nogc
{
    return c == '"' || c == '\'' || c == '.' || c == ',' || c == 0x066B;
}

// Whether the JDK word BreakIterator has a boundary at UTF-8 offset i: letters and digits join, a mark joins what
// precedes it, and one mid-word (mid-num) character joins two letters (digits).
private bool isBoundary(scope const(char)[] s, size_t i) pure nothrow @nogc
{
    if (i == 0 || i >= s.length)
        return true;
    size_t back = i;
    size_t ahead = i;
    const p = before(s, back);
    const n = decodeUtf8(s, ahead);
    const kp = kind(p) == Kind.mark ? Kind.letter : kind(p);
    const kn = kind(n);
    if (kn == Kind.mark || (kp != Kind.other && kn != Kind.other))
        return false;
    if (kp != Kind.other && ahead < s.length)
        return !joins(kp, n, kind(decodeUtf8(s, ahead)));
    if (kn != Kind.other && back > 0)
    {
        const k = kind(before(s, back));
        return !joins(k == Kind.mark ? Kind.letter : k, p, kn);
    }
    return true;
}

// Whether punctuation `mid` between a code point of kind `left` and one of kind `right` stays inside the word.
private bool joins(Kind left, dchar mid, Kind right) pure nothrow @nogc
{
    if (left == Kind.letter && right == Kind.letter)
        return isMidWord(mid);
    if (left == Kind.digit && right == Kind.digit)
        return isMidNum(mid);
    return false;
}

// The code point that ends at UTF-8 offset i, moving i back to its start.
private dchar before(scope const(char)[] s, ref size_t i) pure nothrow @nogc
{
    size_t start = i - 1;
    while (start > 0 && i - start < 4 && (s[start] & 0xC0) == 0x80)
        --start;
    i = start;
    size_t index = start;
    return decodeUtf8(s, index);
}
