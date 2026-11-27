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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Integer.java (parseInt, decode),
// java/lang/Character.java (digit) and java/lang/NumberFormatException.java (forInputString).
// Modified by the Flint authors: the parsers return a status instead of throwing, so the boxed-type leaves
// stay nothrow @nogc until they report a failure; text is UTF-8, decoded one BMP character at a time, so
// Java's UTF-16 code units and their digit values are unchanged; the exception messages are built only in a
// zero-parameter template that imports flint.java.lang on first use (S-132).

/// Java's `Integer.parseInt` and `Integer.decode` for the boxed-type leaves (`Byte`, `Short`).
module flint.java.internal.integers;

import flint.java.lang.character.decimaldigits : javaDecimalDigit;

@safe:

/// The outcome of a parse, naming the `NumberFormatException` message Java reports.
package(flint) enum IntParse : ubyte
{
    ok,
    /// `radix N less than Character.MIN_RADIX`
    radixTooSmall,
    /// `radix N greater than Character.MAX_RADIX`
    radixTooLarge,
    /// `For input string: "s"`, with ` under radix N` when the radix isn't 10
    badInput,
    /// `Zero length string` (decode)
    zeroLength,
    /// `Sign character in wrong position` (decode)
    signInWrongPosition,
}

/// Java's `Character.digit(char, radix)`: the value of one UTF-16 code unit in `radix`, or -1. Decimal digits of
/// every BMP script, ASCII letters and the fullwidth Latin letters U+FF21..U+FF3A and U+FF41..U+FF5A count.
package(flint) int javaDigit(uint unit, int radix) pure nothrow @nogc
{
    if (radix < 2 || radix > 36)
        return -1;
    uint value = javaDecimalDigit(unit);
    if (value == uint.max)
    {
        if (unit - 'A' < 26)
            value = unit - 'A' + 10;
        else if (unit - 'a' < 26)
            value = unit - 'a' + 10;
        else if (unit - 0xFF21 < 26)
            value = unit - 0xFF21 + 10;
        else if (unit - 0xFF41 < 26)
            value = unit - 0xFF41 + 10;
        else
            return -1;
    }
    return value < radix ? cast(int) value : -1;
}

// The next character of UTF-8 text as Java's code unit, or uint.max for anything that isn't one BMP character
// (malformed or overlong bytes, or a supplementary character, whose surrogate units have no digit value).
private uint nextUnit(scope const(char)[] s, ref size_t i) pure nothrow @nogc
{
    const uint lead = s[i++];
    if (lead < 0x80)
        return lead;
    size_t width;
    uint unit;
    if ((lead & 0xE0) == 0xC0)
    {
        width = 1;
        unit = lead & 0x1F;
    }
    else if ((lead & 0xF0) == 0xE0)
    {
        width = 2;
        unit = lead & 0x0F;
    }
    else
        return uint.max;
    foreach (_; 0 .. width)
    {
        if (i == s.length || (s[i] & 0xC0) != 0x80)
            return uint.max;
        unit = (unit << 6) | (s[i++] & 0x3F);
    }
    return unit < (width == 1 ? 0x80 : 0x800) ? uint.max : unit;
}

// Java's digit loop: accumulate negatively against the limit, so MIN_VALUE parses and overflow is caught.
private bool accumulate(scope const(char)[] digits, int radix, bool negative, out int result) pure nothrow @nogc
{
    const int limit = negative ? int.min : -int.max;
    const int multmin = limit / radix;
    int value = 0;
    size_t i;
    while (i < digits.length)
    {
        const digit = javaDigit(nextUnit(digits, i), radix);
        if (digit < 0 || value < multmin)
            return false;
        value *= radix;
        if (value < limit + digit)
            return false;
        value -= digit;
    }
    result = negative ? value : -value;
    return true;
}

/// Java's `Integer.parseInt(s, radix)`. A D null string is Java's `""`.
package(flint) IntParse parseJavaInt(scope const(char)[] s, int radix, out int result) pure nothrow @nogc
{
    if (radix < 2)
        return IntParse.radixTooSmall;
    if (radix > 36)
        return IntParse.radixTooLarge;
    if (s.length == 0)
        return IntParse.badInput;
    bool negative;
    size_t start;
    if (s[0] < '0') // Possible leading "+" or "-"
    {
        if (s[0] == '-')
            negative = true;
        else if (s[0] != '+')
            return IntParse.badInput;
        if (s.length == 1) // Cannot have lone "+" or "-"
            return IntParse.badInput;
        start = 1;
    }
    return accumulate(s[start .. $], radix, negative, result) ? IntParse.ok : IntParse.badInput;
}

/// Where `Integer.decode` found the digits: Java retries a failed parse as `parseInt((negative ? "-" : "") +
/// nm.substring(digits), radix)`, so its message names that text.
package(flint) struct DecodeSite
{
    size_t digits;
    int radix = 10;
    bool negative;
}

// Java's radix specifier after the sign: `0x`, `0X` or `#` for hexadecimal, or a `0` with more text for octal.
// Sets `radix` and returns the specifier's length. Java's `nm.length() > 1 + index` counts UTF-16 units, and the
// UTF-8 byte count is above one exactly when the unit count is.
private size_t radixPrefix(scope const(char)[] rest, ref int radix) pure nothrow @nogc
{
    if (rest.length >= 2 && rest[0] == '0' && (rest[1] == 'x' || rest[1] == 'X'))
    {
        radix = 16;
        return 2;
    }
    if (rest.length >= 1 && rest[0] == '#')
    {
        radix = 16;
        return 1;
    }
    if (rest.length >= 2 && rest[0] == '0')
    {
        radix = 8;
        return 1;
    }
    return 0;
}

/// Java's `Integer.decode(nm)`: an optional sign, then `0x`, `0X` or `#` for hexadecimal or a leading `0` for
/// octal. Java parses the digits once without the sign and, when that fails (MIN_VALUE or bad input), once more
/// with it; both reach the same value or the same failure, so one signed pass stands for the two.
package(flint) IntParse decodeJavaInt(scope const(char)[] nm, out int result, out DecodeSite site) pure nothrow @nogc
{
    if (nm.length == 0)
        return IntParse.zeroLength;
    size_t index;
    if (nm[0] == '-')
    {
        site.negative = true;
        index++;
    }
    else if (nm[0] == '+')
        index++;
    index += radixPrefix(nm[index .. $], site.radix);
    site.digits = index;
    if (index < nm.length && (nm[index] == '-' || nm[index] == '+'))
        return IntParse.signInWrongPosition;
    if (index == nm.length)
        return IntParse.badInput;
    return accumulate(nm[index .. $], site.radix, site.negative, result) ? IntParse.ok : IntParse.badInput;
}

/// Java's `Integer.toString(i)` in GC memory. A template, so the caller's object instantiates the array copy: a
/// library object would otherwise resolve it from whichever archive member emitted it first, and link that
/// member's module records.
package(flint) string javaIntText()(long value) pure nothrow
{
    char[20] text = void;
    size_t at = text.length;
    ulong magnitude = value < 0 ? -cast(ulong) value : cast(ulong) value;
    do
    {
        text[--at] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude);
    if (value < 0)
        text[--at] = '-';
    return text[at .. $].idup;
}

/// Throws the `NumberFormatException` Java reports for `status` while parsing `s` in `radix`.
package(flint) noreturn throwIntParse()(IntParse status, string s, int radix)
{
    import flint.java.lang : NumberFormatException;

    final switch (status)
    {
    case IntParse.radixTooSmall:
        throw new NumberFormatException("radix " ~ javaIntText(radix) ~ " less than Character.MIN_RADIX");
    case IntParse.radixTooLarge:
        throw new NumberFormatException("radix " ~ javaIntText(radix) ~ " greater than Character.MAX_RADIX");
    case IntParse.zeroLength:
        throw new NumberFormatException("Zero length string");
    case IntParse.signInWrongPosition:
        throw new NumberFormatException("Sign character in wrong position");
    case IntParse.ok:
    case IntParse.badInput:
        throw new NumberFormatException(
                "For input string: \"" ~ s ~ "\"" ~ (radix == 10 ? "" : " under radix " ~ javaIntText(radix)));
    }
}

/// Throws the failure of `Integer.decode(nm)`, whose retry names the signed digits.
package(flint) noreturn throwIntDecode()(IntParse status, string nm, DecodeSite site)
{
    if (status != IntParse.badInput)
        throwIntParse(status, nm, site.radix);
    throwIntParse(status, (site.negative ? "-" : "") ~ nm[site.digits .. $], site.radix);
}

/// Throws Java's `Byte`/`Short.parseX` range failure: `Value out of range. Value:"s" Radix:N`.
package(flint) noreturn throwParseRange()(string s, int radix)
{
    import flint.java.lang : NumberFormatException;

    throw new NumberFormatException("Value out of range. Value:\"" ~ s ~ "\" Radix:" ~ javaIntText(radix));
}

/// Throws Java's `Byte`/`Short.decode` range failure: `Value N out of range from input nm`.
package(flint) noreturn throwDecodeRange()(int value, string nm)
{
    import flint.java.lang : NumberFormatException;

    throw new NumberFormatException("Value " ~ javaIntText(value) ~ " out of range from input " ~ nm);
}
