/*
 * Copyright (c) 1996, 2023, Oracle and/or its affiliates. All rights reserved.
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
 * (C) Copyright Taligent, Inc. 1996, 1997 - All Rights Reserved
 * (C) Copyright IBM Corp. 1996 - 1998 - All Rights Reserved
 *
 *   The original version of this source code and documentation is copyrighted
 * and owned by Taligent, Inc., a wholly-owned subsidiary of IBM. These
 * materials are provided under terms of a License Agreement between Taligent
 * and Sun. This technology is protected by multiple US and International
 * patents. This notice and attribution to Taligent may not be removed.
 *   Taligent is a registered trademark of Taligent, Inc.
 *
 */

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/text/DecimalFormat.java (parse, subparse,
// subparseNumber) and DigitList.java (fitsIntoLong, getLong, getDouble).
// Modified by the Flint authors.
module flint.java.text.internal.decimalparse;

import flint.java.internal.math.floatingdecimal : FloatingDecimalStatus, digitListToDouble;
import flint.java.lang.character.decimaldigits : javaDecimalDigit;
import flint.java.text.internal.decimalfixed : DecimalFixedPattern;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, encodeSymbol;

@safe:

package(flint.java.text):

struct DecimalParseOptions
{
    bool groupingUsed = true;
    bool integerOnly;
    int multiplier = 1;
    // isParseBigDecimal: finite results stay a DigitList for decimalparsebig.
    bool parseBigDecimal;
}

enum DecimalParseKind : ubyte
{
    failed,
    longValue,
    doubleValue,
    // More significant digits than the caller's buffer holds.
    capacity,
    // The DigitList fields describe a BigDecimal result; see decimalparsebig.
    bigDecimal,
}

/// Offsets are UTF-8 byte offsets into the parsed text.
struct DecimalParseResult
{
    DecimalParseKind kind;
    size_t index;
    ptrdiff_t errorIndex = -1;
    bool positive;
    bool infinite;
    long longValue;
    double doubleValue = 0;
    // Java's DigitList: `count` digits, the first `stored` in the caller buffer and the rest zeros.
    int decimalAt;
    size_t count;
    size_t stored;
}

/// DecimalFormat.parse(String, ParsePosition) for a fixed-point or exponent pattern; a currency pattern reads the
/// monetary separators.
/// `digits` receives the significant digits, which DigitList grows without bound.
/// The pattern's affixes are expanded with the same `symbols`, which must pass `bodySymbolsEncodable`.
DecimalParseResult parseDecimal(scope const(char)[] text, size_t start, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, DecimalParseOptions options, scope char[] digits) pure nothrow @nogc
{
    DecimalParseResult result;
    result.index = start;
    if (regionMatches(text, start, symbols.nan))
    {
        result.index = start + symbols.nan.length;
        result.kind = DecimalParseKind.doubleValue;
        result.doubleValue = double.nan;
        return result;
    }
    if (!subparse(text, pattern, symbols, options, digits, result))
        return result;
    if (result.kind == DecimalParseKind.capacity)
        return result;
    // Infinity and a zero multiplier answer a Double before Java consults isParseBigDecimal.
    if (options.parseBigDecimal && !result.infinite && options.multiplier != 0)
    {
        result.kind = DecimalParseKind.bigDecimal;
        return result;
    }
    evaluate(options, digits, result);
    return result;
}

private:

struct ParsedDigits
{
    int decimalAt;
    size_t count;
    size_t stored;
    bool overflow;
}

bool regionMatches(scope const(char)[] text, size_t position, scope const(char)[] other) pure nothrow @nogc
{
    return position <= text.length && other.length <= text.length - position
        && text[position .. position + other.length] == other;
}

// Takes the longer of two matching affixes and keeps both when they have the same length.
void longest(ref bool positive, ref bool negative, size_t positiveLength, size_t negativeLength) pure nothrow @nogc
{
    if (positive && negative)
    {
        if (positiveLength > negativeLength)
            negative = false;
        else if (positiveLength < negativeLength)
            positive = false;
    }
}

bool subparse(scope const(char)[] text, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, DecimalParseOptions options, scope char[] digits,
        ref DecimalParseResult result) pure nothrow @nogc
{
    const oldStart = result.index;
    bool gotPositive = regionMatches(text, oldStart, pattern.positive.prefix);
    bool gotNegative = regionMatches(text, oldStart, pattern.negative.prefix);
    longest(gotPositive, gotNegative, pattern.positive.prefix.length, pattern.negative.prefix.length);
    if (!gotPositive && !gotNegative)
    {
        result.errorIndex = oldStart;
        return false;
    }
    size_t position = oldStart + (gotPositive ? pattern.positive.prefix.length : pattern.negative.prefix.length);

    if (!subparseNumber(text, position, symbols, pattern.currencyFormat, options, digits, result))
    {
        result.errorIndex = oldStart;
        return false;
    }

    gotPositive = gotPositive && regionMatches(text, position, pattern.positive.suffix);
    gotNegative = gotNegative && regionMatches(text, position, pattern.negative.suffix);
    longest(gotPositive, gotNegative, pattern.positive.suffix.length, pattern.negative.suffix.length);
    if (gotPositive == gotNegative)
    {
        result.errorIndex = position;
        return false;
    }
    const end = position + (gotPositive ? pattern.positive.suffix.length : pattern.negative.suffix.length);
    if (end == oldStart)
    {
        result.errorIndex = position;
        return false;
    }
    result.index = end;
    result.positive = gotPositive;
    return true;
}

pure nothrow @nogc bool subparseNumber(scope const(char)[] text, ref size_t position,
        ref scope const DecimalSymbolData symbols, bool monetary, DecimalParseOptions options,
        scope char[] digits, ref DecimalParseResult result)
{
    if (regionMatches(text, position, symbols.infinity))
    {
        position += symbols.infinity.length;
        result.infinite = true;
        return true;
    }
    ParsedDigits parsed;
    int exponent;
    if (!scanDigits(text, position, symbols, monetary, options, digits, parsed, exponent))
        return false;
    // Java adds the truncated exponent in 32-bit arithmetic.
    result.decimalAt = cast(int)(cast(uint) parsed.decimalAt + cast(uint) exponent);
    result.count = parsed.count;
    result.stored = parsed.stored;
    if (parsed.overflow)
        result.kind = DecimalParseKind.capacity;
    return true;
}

// One UTF-16 code unit as Java's charAt sees it, or uint.max for a supplementary or malformed sequence.
uint unitAt(scope const(char)[] text, size_t position, out size_t width) pure nothrow @nogc
{
    const lead = text[position];
    width = 1;
    if (lead < 0x80)
        return lead;
    if (lead >= 0xC2 && lead < 0xE0 && position + 1 < text.length && (text[position + 1] & 0xC0) == 0x80)
    {
        width = 2;
        return ((lead & 0x1F) << 6) | (text[position + 1] & 0x3F);
    }
    if (lead >= 0xE0 && lead < 0xF0 && position + 2 < text.length && (text[position + 1] & 0xC0) == 0x80
            && (text[position + 2] & 0xC0) == 0x80)
    {
        width = 3;
        return ((lead & 0x0F) << 12) | ((text[position + 1] & 0x3F) << 6) | (text[position + 2] & 0x3F);
    }
    return uint.max;
}

pure nothrow @nogc bool scanDigits(scope const(char)[] text, ref size_t position,
        ref scope const DecimalSymbolData symbols, bool monetary, DecimalParseOptions options,
        scope char[] digits, ref ParsedDigits parsed, out int exponent)
{
    const decimal = monetary ? symbols.monetaryDecimalSeparator : symbols.decimalSeparator;
    const grouping = monetary ? symbols.monetaryGroupingSeparator : symbols.groupingSeparator;
    bool sawDecimal;
    bool sawDigit;
    // Zeros after the last stored digit, which DigitList appends but this buffer leaves implicit.
    size_t zeros;
    ptrdiff_t backup = -1;
    for (; position < text.length; ++position)
    {
        size_t width;
        const unit = unitAt(text, position, width);
        const digit = digitValue(unit, symbols.zeroDigit);
        if (digit <= 9)
        {
            backup = -1;
            sawDigit = true;
            appendDigit(digit, sawDecimal, digits, parsed, zeros);
            position += width - 1;
        }
        else if (unit == decimal)
        {
            if (options.integerOnly || sawDecimal)
                break;
            parsed.decimalAt = cast(int) parsed.count;
            sawDecimal = true;
            position += width - 1;
        }
        else if (unit == grouping && options.groupingUsed)
        {
            if (sawDecimal)
                break;
            // A grouping separator must be followed by a digit, or the scan resumes before it.
            backup = position;
            position += width - 1;
        }
        else
        {
            if (regionMatches(text, position, symbols.exponentSeparator))
                scanExponent(text, position, symbols, exponent);
            break;
        }
    }
    if (backup != -1)
        position = cast(size_t) backup;
    if (!sawDecimal)
        parsed.decimalAt = cast(int) parsed.count;
    return sawDigit || parsed.count != 0;
}

pure nothrow @nogc void appendDigit(uint digit, bool sawDecimal, scope char[] digits,
        ref ParsedDigits parsed, ref size_t zeros)
{
    if (digit == 0 && parsed.count == 0)
    {
        // Leading zeros only move the decimal point once it has been seen.
        if (sawDecimal)
            --parsed.decimalAt;
        return;
    }
    ++parsed.count;
    if (digit == 0)
    {
        ++zeros;
        return;
    }
    if (zeros + 1 > digits.length - parsed.stored || parsed.overflow)
    {
        parsed.overflow = true;
        return;
    }
    digits[parsed.stored .. parsed.stored + zeros] = '0';
    parsed.stored += zeros;
    zeros = 0;
    digits[parsed.stored++] = cast(char)('0' + digit);
}

// Java tries the locale zero digit first, then Character.digit. Its difference is int arithmetic, so a zero
// digit near U+FFFF does not wrap to U+0000.
uint digitValue(uint unit, wchar zero) pure nothrow @nogc
{
    if (unit == uint.max)
        return uint.max;
    if (unit - zero <= 9)
        return unit - zero;
    return javaDecimalDigit(unit);
}

// Parses the exponent as Java's recursive subparse does, with an empty positive prefix and the minus sign text
// as the negative prefix, advancing only if it fits into a long.
void scanExponent(scope const(char)[] text, ref size_t position, ref scope const DecimalSymbolData symbols,
        out int exponent) pure nothrow @nogc
{
    size_t at = position + symbols.exponentSeparator.length;
    char[3] minus;
    const minusWidth = encodeSymbol(symbols.minusSign, minus);
    const negative = regionMatches(text, at, minus[0 .. minusWidth]);
    if (negative)
        at += minusWidth;
    ExponentDigits parsed;
    if (!scanExponentDigits(text, at, symbols.zeroDigit, parsed) || !exponentFits(parsed, !negative))
        return;
    ulong magnitude;
    foreach (i; 0 .. parsed.count)
        magnitude = magnitude * 10 + (i < parsed.stored ? parsed.significant[i] - '0' : 0);
    position = at;
    // Java narrows the long exponent to int before negating it.
    const narrowed = cast(int) magnitude;
    exponent = negative ? -narrowed : narrowed;
}

// DigitList.fitsIntoLong ignores the zeros that end the exponent and admits up to 19 digits.
struct ExponentDigits
{
    char[19] significant;
    size_t stored;
    size_t count;
}

pure nothrow @nogc bool scanExponentDigits(scope const(char)[] text, ref size_t at, wchar zero,
        ref ExponentDigits parsed)
{
    bool sawDigit;
    for (; at < text.length; ++at)
    {
        size_t width;
        const unit = unitAt(text, at, width);
        const digit = digitValue(unit, zero);
        if (digit > 9)
            break;
        sawDigit = true;
        at += width - 1;
        if (digit == 0 && parsed.count == 0)
            continue;
        if (++parsed.count > parsed.significant.length || digit == 0)
            continue;
        parsed.significant[parsed.stored .. parsed.count - 1] = '0';
        parsed.significant[parsed.count - 1] = cast(char)('0' + digit);
        parsed.stored = parsed.count;
    }
    return sawDigit;
}

bool exponentFits(ref scope const ExponentDigits parsed, bool positive) pure nothrow @nogc
{
    enum maximum = parsed.significant.length;
    if (parsed.count != maximum)
        return parsed.count < maximum;
    return fitsIntoLongDigits(parsed.significant[0 .. parsed.stored], cast(int) maximum, positive);
}

immutable longMinRep = "9223372036854775808";

// DigitList.fitsIntoLong after trailing zeros are trimmed, for 1 <= count <= decimalAt.
bool fitsIntoLongDigits(scope const(char)[] digits, int decimalAt, bool positive) pure nothrow @nogc
{
    if (decimalAt > longMinRep.length)
        return false;
    if (decimalAt < longMinRep.length)
        return true;
    foreach (i, digit; digits)
    {
        if (digit != longMinRep[i])
            return digit < longMinRep[i];
    }
    return digits.length < decimalAt || !positive;
}

pure nothrow @nogc bool fitsIntoLong(ref scope const DecimalParseResult result,
        scope const(char)[] digits, bool ignoreNegativeZero)
{
    // Trailing zeros are never stored, so the stored digits are the trimmed DigitList.
    if (result.stored == 0)
        return result.positive || ignoreNegativeZero;
    if (result.decimalAt < cast(long) result.stored)
        return false;
    return fitsIntoLongDigits(digits[0 .. result.stored], result.decimalAt, result.positive);
}

long getLong(ref scope const DecimalParseResult result, scope const(char)[] digits) pure nothrow @nogc
{
    if (result.stored == 0)
        return 0;
    if (result.decimalAt == longMinRep.length && digits[0 .. result.stored] == longMinRep)
        return long.min;
    ulong value;
    foreach (i; 0 .. result.decimalAt)
        value = value * 10 + (i < result.stored ? digits[i] - '0' : 0);
    return cast(long) value;
}

void evaluate(DecimalParseOptions options, scope const(char)[] digits, ref DecimalParseResult result) pure nothrow @nogc
{
    result.kind = DecimalParseKind.doubleValue;
    if (result.infinite)
    {
        result.doubleValue = result.positive == (options.multiplier >= 0) ? double.infinity : -double.infinity;
        return;
    }
    if (options.multiplier == 0)
    {
        result.doubleValue = result.stored == 0 ? double.nan : (result.positive ? double.infinity : -double.infinity);
        return;
    }
    if (!fitsIntoLong(result, digits, options.integerOnly))
    {
        toDouble(options, digits, result);
        return;
    }
    long value = getLong(result, digits);
    const gotLongMinimum = value < 0;
    double quotient = 0;
    bool gotDouble;
    if (options.multiplier != 1)
        gotDouble = divide(value, options.multiplier, quotient);
    if (!result.positive && !gotLongMinimum)
    {
        quotient = -quotient;
        value = -cast(ulong) value;
    }
    if (gotDouble)
    {
        // The quotient magnitude is at most 2^62, so the conversion is exact Java narrowing.
        value = cast(long) quotient;
        gotDouble = quotient != cast(double) value && !options.integerOnly;
    }
    if (gotDouble)
    {
        result.doubleValue = quotient;
        return;
    }
    result.kind = DecimalParseKind.longValue;
    result.longValue = value;
}

// DigitList.getDouble, then the multiplier, sign and long re-narrowing of DecimalFormat.parse.
void toDouble(DecimalParseOptions options, scope const(char)[] digits, ref DecimalParseResult result) pure nothrow @nogc
{
    const converted = digitListToDouble(digits[0 .. result.stored], result.count, result.decimalAt);
    if (converted.status != FloatingDecimalStatus.ok)
    {
        result.kind = DecimalParseKind.capacity;
        return;
    }
    double value = converted.value;
    if (options.multiplier != 1)
        value /= options.multiplier;
    if (!result.positive)
        value = -value;
    result.doubleValue = value;
    if (options.multiplier == 1)
        return;
    const narrowed = javaLong(value);
    const negativeZero = value == 0.0 && 1 / value < 0.0;
    if ((value != cast(double) narrowed || negativeZero) && !options.integerOnly)
        return;
    result.kind = DecimalParseKind.longValue;
    result.longValue = narrowed;
}

// Java's double-to-long narrowing: NaN is zero and out-of-range values saturate.
long javaLong(double value) pure nothrow @nogc
{
    if (value != value)
        return 0;
    if (value >= 0x1p63)
        return long.max;
    if (value <= -0x1p63)
        return long.min;
    return cast(long) value;
}

// Java long division by an int multiplier; returns true when the quotient is a double.
bool divide(ref long value, int multiplier, out double quotient) pure nothrow @nogc
{
    // Java defines Long.MIN_VALUE / -1 as Long.MIN_VALUE with remainder zero.
    if (multiplier == -1)
    {
        value = -cast(ulong) value;
        return false;
    }
    if (value % multiplier == 0)
    {
        value /= multiplier;
        return false;
    }
    quotient = cast(double) value / multiplier;
    return true;
}
