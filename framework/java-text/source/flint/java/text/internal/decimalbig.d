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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/text/DecimalFormat.java
// (format(BigDecimal, ...) and format(BigInteger, ..., formatLong = false)) and DigitList.java
// (set(boolean, BigDecimal, int, boolean), set(boolean, BigInteger, int) and the String digit reader).
// Modified by the Flint authors.
/// Arbitrary-precision DecimalFormat rendering over the canonical decimal text of a BigDecimal or BigInteger.
module flint.java.text.internal.decimalbig;

import flint.java.text.internal.decimalfixed : DecimalFieldSpans, DecimalFixedPattern;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;

@safe:

package(flint.java.text):

enum DecimalBigStatus : ubyte
{
    complete,
    /// RoundingMode.UNNECESSARY met a discarded nonzero digit; Java throws ArithmeticException.
    inexact,
    /// The decimal position lies where Java's int arithmetic wraps; that output is not reproduced.
    exponentRange,
}

/// Formats a BigDecimal as DecimalFormat.format(BigDecimal) does after its multiplier.
/// `text` is BigDecimal.toString() of the multiplied magnitude and `negative` its sign; `digits` is scratch
/// for the DigitList digits. Returns the required byte count, leaves a short buffer untouched and writes
/// nothing unless the status is complete.
pure nothrow @nogc size_t renderBigDecimal(scope const(char)[] text, bool negative,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols, scope char[] digits,
        scope char[] output, FixedRoundingMode mode, out DecimalBigStatus status, scope DecimalFieldSpans* spans = null)
in (digits.length >= text.length)
{
    const exponential = pattern.minimumExponentDigits != 0;
    uint maximumDigits = pattern.maximumFractionDigits;
    if (exponential)
        maximumDigits = totalDigitLimit(pattern);
    return renderBig(text, negative, maximumDigits, true, pattern, symbols, digits, output, mode, status, spans);
}

/// Formats a BigInteger as DecimalFormat.format(BigInteger) does after its multiplier.
/// `text` is BigInteger.toString() of the multiplied magnitude; the other arguments are as for renderBigDecimal.
pure nothrow @nogc size_t renderBigInteger(scope const(char)[] text, bool negative,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols, scope char[] digits,
        scope char[] output, FixedRoundingMode mode, out DecimalBigStatus status, scope DecimalFieldSpans* spans = null)
in (digits.length >= text.length)
{
    // DigitList.set(BigInteger) rounds only to a positive total digit limit, and never in fixed point.
    uint maximumDigits = uint.max;
    if (pattern.minimumExponentDigits != 0 && totalDigitLimit(pattern) != 0)
        maximumDigits = totalDigitLimit(pattern);
    return renderBig(text, negative, maximumDigits, false, pattern, symbols, digits, output, mode, status, spans);
}

private:

// maxInt + maxFrac. Java replaces an int overflow with Integer.MAX_VALUE; both exceed any digit count.
uint totalDigitLimit(ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
{
    return pattern.maximumIntegerDigits + pattern.maximumFractionDigits;
}

// `fixedPoint` is DigitList's flag: `maximumDigits` then counts fraction digits instead of total digits.
pure nothrow @nogc size_t renderBig(scope const(char)[] text, bool negative, uint maximumDigits,
        bool fixedPoint, ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols,
        scope char[] digits, scope char[] output, FixedRoundingMode mode, out DecimalBigStatus status,
        scope DecimalFieldSpans* fields)
{
    import flint.java.text.internal.decimaldigitlist : roundFixed, roundSignificant;
    import flint.java.text.internal.decimalexponent : renderExponentDigits;
    import flint.java.text.internal.decimalfixed : renderFixedDigits;

    long position;
    size_t count = readDigits(text, digits, position);
    const exponential = pattern.minimumExponentDigits != 0;
    const span = exponential ? exponentSpan(pattern) : 0;
    if (count != 0 && (position > int.max || !inIntRange(position, span)))
    {
        status = DecimalBigStatus.exponentRange;
        return 0;
    }
    int decimalAt = cast(int) position;
    FixedRoundingStatus rounding;
    // A BigDecimal is exact and has not been rounded by its conversion to text.
    if (exponential || !fixedPoint)
        count = roundSignificant(digits[0 .. count], decimalAt, maximumDigits, false, true, negative, mode, rounding);
    else
        count = roundFixed(digits[0 .. count], decimalAt, maximumDigits, false, true, negative, mode, rounding);
    if (rounding == FixedRoundingStatus.inexact)
    {
        status = DecimalBigStatus.inexact;
        return 0;
    }
    // A carry out of Integer.MAX_VALUE wraps the int decimal position in Java.
    if (count != 0 && !inIntRange(decimalAt, span))
    {
        status = DecimalBigStatus.exponentRange;
        return 0;
    }
    if (count == 0)
        decimalAt = 0;
    if (exponential)
        return renderExponentDigits(digits[0 .. count], decimalAt, negative, pattern, symbols, output, fields, true);
    return renderFixedDigits(digits[0 .. count], decimalAt, negative, pattern, symbols, output, fields, true);
}

// The exponential layout subtracts the repeat or the minimum integer digits from the decimal position and
// negates the result; with this margin none of those int operations wraps.
uint exponentSpan(ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
{
    const repeat = pattern.maximumIntegerDigits;
    const repeating = repeat > 1 && repeat > pattern.minimumIntegerDigits;
    return repeating ? repeat : pattern.minimumIntegerDigits;
}

bool inIntRange(long position, uint span) pure nothrow @nogc
{
    return position - span > int.min;
}

// DigitList.set(boolean, String, ...): digits from the first nonzero one, the decimal point and an E exponent.
// Unlike Java's int, the position is exact so that the caller can detect where Java would wrap.
size_t readDigits(scope const(char)[] text, scope char[] digits, out long decimalAt) pure nothrow @nogc
{
    size_t count;
    long point = -1;
    long exponent;
    long leadingZerosAfterPoint;
    bool nonZeroSeen;
    foreach (i, c; text)
    {
        if (c == '.')
            point = count;
        else if (c == 'e' || c == 'E')
        {
            exponent = readExponent(text[i + 1 .. $]);
            break;
        }
        else
        {
            if (!nonZeroSeen)
            {
                nonZeroSeen = c != '0';
                if (!nonZeroSeen && point != -1)
                    ++leadingZerosAfterPoint;
            }
            if (nonZeroSeen)
                digits[count++] = c;
        }
    }
    decimalAt = point == -1 ? count : point;
    if (nonZeroSeen)
        decimalAt += exponent - leadingZerosAfterPoint;
    return count;
}

// BigDecimal.toString() writes at most ten exponent digits, so a long holds the exact value.
long readExponent(scope const(char)[] text) pure nothrow @nogc
{
    bool negative;
    if (text.length != 0 && (text[0] == '-' || text[0] == '+'))
    {
        negative = text[0] == '-';
        text = text[1 .. $];
    }
    long value;
    foreach (c; text)
    {
        if (c < '0' || c > '9' || value > uint.max)
            break;
        value = value * 10 + (c - '0');
    }
    return negative ? -value : value;
}
