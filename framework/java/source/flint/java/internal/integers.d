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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Integer.java (parseInt, parseUnsignedInt,
// decode, toString), java/lang/Long.java (parseLong, parseUnsignedLong, decode, toUnsignedString),
// java/lang/Character.java (digit) and java/lang/NumberFormatException.java (forInputString, forCharSequence).
// Modified by the Flint authors: the parsers return a status instead of throwing, so the boxed-type leaves
// stay nothrow @nogc until they report a failure; text is UTF-8, decoded one BMP character at a time, so
// Java's UTF-16 code units and their digit values are unchanged; the exception messages are built only in a
// zero-parameter template that imports flint.java.lang on first use (S-132).

/// Java's integer parsing and formatting for the boxed-type leaves (`Byte`, `Short`, `Integer`, `Long`).
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
    /// `Illegal leading minus sign on unsigned string s.`
    leadingMinus,
    /// `String value s exceeds range of unsigned int.`
    unsignedIntRange,
    /// `String value s exceeds range of unsigned long.`
    unsignedLongRange,
    /// `Bad digit at end of s` (parseUnsignedLong)
    badDigitAtEnd,
    /// `Error at index N in: "s"`, without the last UTF-16 unit of `s` (parseUnsignedLong)
    errorAtIndex,
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

// Java's digit loop for `int` or `long`: accumulate negatively against the limit, so MIN_VALUE parses and overflow
// is caught. On failure, `failure` is the UTF-16 index in `digits` of the character Java rejects.
pure nothrow @nogc private bool accumulate(T)(scope const(char)[] digits, int radix, bool negative,
        out T result, out size_t failure)
{
    const T limit = negative ? T.min : -T.max;
    const T multmin = limit / radix;
    T value = 0;
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
        failure++; // A digit is one BMP character, so one UTF-16 unit.
    }
    result = negative ? value : -value;
    return true;
}

/// Java's `s.length()`: the UTF-16 units of UTF-8 text. A four-byte sequence is a surrogate pair.
package(flint) size_t javaLength(scope const(char)[] s) pure nothrow @nogc
{
    size_t units;
    foreach (c; s)
        units += ((c & 0xC0) != 0x80) + (c >= 0xF0);
    return units;
}

// Java's parseInt/parseLong(String, radix) for `int` or `long`.
private IntParse parseSigned(T)(scope const(char)[] s, int radix, out T result) pure nothrow @nogc
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
    size_t failure;
    return accumulate(s[start .. $], radix, negative, result, failure) ? IntParse.ok : IntParse.badInput;
}

/// Java's `Integer.parseInt(s, radix)`. A D null string is Java's `""`.
package(flint) IntParse parseJavaInt(scope const(char)[] s, int radix, out int result) pure nothrow @nogc
{
    return parseSigned(s, radix, result);
}

/// Java's `Long.parseLong(s, radix)`. A D null string is Java's `""`.
package(flint) IntParse parseJavaLong(scope const(char)[] s, int radix, out long result) pure nothrow @nogc
{
    return parseSigned(s, radix, result);
}

/++
Java's `Integer.parseUnsignedInt(s, radix)`. Java parses short text with `parseInt` and longer text with
`Long.parseLong`; both reach the same value or the same message here, so one `long` parse stands for the two.
+/
package(flint) IntParse parseJavaUnsignedInt(scope const(char)[] s, int radix, out int result) pure nothrow @nogc
{
    if (s.length == 0)
        return IntParse.badInput;
    if (s[0] == '-')
        return IntParse.leadingMinus;
    long value;
    const status = parseSigned(s, radix, value);
    if (status != IntParse.ok)
        return status;
    if ((value & 0xffff_ffff_0000_0000L) != 0)
        return IntParse.unsignedIntRange;
    result = cast(int) value;
    return IntParse.ok;
}

/++
Java's `Long.parseUnsignedLong(s, radix)`. Text of at most 12 UTF-16 units (18 in radix 10) is `parseLong`; longer
text parses all but its last unit as `parseLong(s, 0, len - 1, radix)`, whose failure is `errorAtIndex` at the
UTF-16 index `failure`, then adds the last digit under Java's overflow guard.
+/
package(flint) pure nothrow @nogc IntParse parseJavaUnsignedLong(scope const(char)[] s, int radix,
        out long result, out size_t failure)
{
    if (s.length == 0)
        return IntParse.badInput;
    if (s[0] == '-')
        return IntParse.leadingMinus;
    const units = javaLength(s);
    if (units <= 12 || (radix == 10 && units <= 18))
        return parseSigned(s, radix, result);
    if (radix < 2)
        return IntParse.radixTooSmall;
    if (radix > 36)
        return IntParse.radixTooLarge;
    return parseLastDigitApart(s, units, radix, result, failure);
}

// Java's parseUnsignedLong for text over the parseLong limit, in a valid radix: parseLong(s, 0, len - 1, radix),
// then the last digit under the overflow guard.
pure nothrow @nogc private IntParse parseLastDigitApart(scope const(char)[] s, size_t units, int radix,
        out long result, out size_t failure)
{
    size_t start;
    if (s[0] < '0') // Possible leading "+"
    {
        if (s[0] != '+')
            return IntParse.errorAtIndex;
        start = 1;
    }
    const last = lastCharStart(s);
    long first;
    if (!accumulate(s[start .. last], radix, false, first, failure))
    {
        failure += start;
        return IntParse.errorAtIndex;
    }
    if (s[last] >= 0xF0)
    {
        // The last unit is a low surrogate, so the prefix ends with its high surrogate, which is no digit.
        failure = units - 2;
        return IntParse.errorAtIndex;
    }
    size_t at = last;
    const second = javaDigit(nextUnit(s, at), radix);
    if (second < 0)
        return IntParse.badDigitAtEnd;
    result = first * radix + second;
    // Java's guard: see Long.parseUnsignedLong for the proof that it detects exactly the overflowing values.
    const int guard = radix * cast(int)(cast(ulong) first >>> 57);
    if (guard >= 128 || (result >= 0 && guard >= 128 - 36))
        return IntParse.unsignedLongRange;
    return IntParse.ok;
}

// The byte offset where the last UTF-8 character of non-empty `s` begins.
private size_t lastCharStart(scope const(char)[] s) pure nothrow @nogc
{
    size_t at = s.length;
    foreach (_; 0 .. 4) // A UTF-8 character has at most three continuation bytes.
    {
        at--;
        if (at == 0 || (s[at] & 0xC0) != 0x80)
            break;
    }
    return at;
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
    return decodeSigned(nm, result, site);
}

/// Java's `Long.decode(nm)`, as `decodeJavaInt` describes.
package(flint) IntParse decodeJavaLong(scope const(char)[] nm, out long result, out DecodeSite site) pure nothrow @nogc
{
    return decodeSigned(nm, result, site);
}

private IntParse decodeSigned(T)(scope const(char)[] nm, out T result, out DecodeSite site) pure nothrow @nogc
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
    size_t failure;
    return accumulate(nm[index .. $], site.radix, site.negative, result, failure) ? IntParse.ok : IntParse.badInput;
}

/++
Writes `magnitude` in `radix` (2 to 36) with Java's lower-case digits, right-aligned in `text`, and returns where
the digits begin. Java's `toString(i, radix)`, `toUnsignedString` and `toHexString` family share this digit loop.
A zero-parameter template, so formatting never links this module's parsers and the Unicode digit table.
+/
package(flint) size_t formatJavaDigits()(ulong magnitude, uint radix, ref char[65] text) pure nothrow @nogc
{
    size_t at = text.length;
    do
    {
        const digit = cast(uint)(magnitude % radix);
        text[--at] = cast(char)(digit < 10 ? '0' + digit : 'a' + digit - 10);
        magnitude /= radix;
    }
    while (magnitude);
    return at;
}

/++
Java's `toString(i, radix)` (`unsigned` false) or `toUnsignedString(i, radix)` (`unsigned` true) in GC memory. A
radix outside 2 to 36 is 10, as in Java. A zero-parameter template, as `javaIntText` explains.
+/
package(flint) string javaRadixText()(long value, int radix, bool unsigned) pure nothrow
{
    if (radix < 2 || radix > 36)
        radix = 10;
    char[65] text = void;
    const negative = !unsigned && value < 0;
    size_t at = formatJavaDigits(negative ? -cast(ulong) value : cast(ulong) value, radix, text);
    if (negative)
        text[--at] = '-';
    return text[at .. $].idup;
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

/++
Throws the `NumberFormatException` Java reports for `status` while parsing `s` in `radix`. `failure` is the
UTF-16 index that `errorAtIndex` names.
+/
package(flint) noreturn throwIntParse()(IntParse status, string s, int radix, size_t failure = 0)
{
    import flint.java.lang : NumberFormatException;

    switch (status)
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
    default:
        throwUnsignedParse(status, s, failure);
    }
}

// The messages of Java's parseUnsignedInt and parseUnsignedLong.
private noreturn throwUnsignedParse()(IntParse status, string s, size_t failure)
{
    import flint.java.lang : NumberFormatException;

    switch (status)
    {
    case IntParse.leadingMinus:
        throw new NumberFormatException("Illegal leading minus sign on unsigned string " ~ s ~ ".");
    case IntParse.unsignedIntRange:
        throw new NumberFormatException("String value " ~ s ~ " exceeds range of unsigned int.");
    case IntParse.unsignedLongRange:
        throw new NumberFormatException("String value " ~ s ~ " exceeds range of unsigned long.");
    case IntParse.badDigitAtEnd:
        throw new NumberFormatException("Bad digit at end of " ~ s);
    default:
        // Java's s.subSequence(0, len - 1) drops the last UTF-16 unit, so a split pair ends in U+FFFD (R14).
        const last = lastCharStart(s);
        const text = s[0 .. last] ~ (s[last] >= 0xF0 ? "\uFFFD" : "");
        throw new NumberFormatException("Error at index " ~ javaIntText(cast(long) failure) ~ " in: \"" ~ text ~ "\"");
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

// DMD -O -inline folds the unreachable division of an inlined literal zero divisor into a "divide by zero" compile
// error (as in flint.java.lang.math), so DMD keeps the unsigned division helpers out of line.
version (DigitalMars)
    private enum bool inlineDivision = false;
else
    private enum bool inlineDivision = true;

/// Java's unsigned `dividend / divisor` for `uint` or `ulong`: `ArithmeticException("/ by zero")` on a zero divisor.
package(flint) T unsignedQuotient(T)(T dividend, T divisor) pure
{
    pragma(inline, inlineDivision);
    if (divisor == 0)
        throwDivideByZero();
    return dividend / divisor;
}

/// Java's unsigned `dividend % divisor` for `uint` or `ulong`: `ArithmeticException("/ by zero")` on a zero divisor.
package(flint) T unsignedRemainder(T)(T dividend, T divisor) pure
{
    pragma(inline, inlineDivision);
    if (divisor == 0)
        throwDivideByZero();
    return dividend % divisor;
}

private noreturn throwDivideByZero()() pure
{
    import flint.java.lang : ArithmeticException;

    throw new ArithmeticException("/ by zero");
}
