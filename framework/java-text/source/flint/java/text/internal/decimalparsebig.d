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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/text/DecimalFormat.java (the isParseBigDecimal
// branch of parse) and DigitList.java (getBigDecimal), with the BigDecimal.divide(BigDecimal) and
// divide(BigDecimal, RoundingMode) results that branch relies on for an int multiplier.
// Modified by the Flint authors.
/// The BigDecimal result of DecimalFormat.parse when isParseBigDecimal is set.
module flint.java.text.internal.decimalparsebig;

import flint.java.text.internal.decimaldigitlist : FixedRoundingMode;
import flint.java.text.internal.decimalparse : DecimalParseKind, DecimalParseResult;

@safe:

package(flint.java.text):

enum DecimalBigParseStatus : ubyte
{
    complete,
    /// RoundingMode.UNNECESSARY met a quotient that does not terminate; Java throws ArithmeticException.
    inexact,
    /// The scale leaves the int range. Java throws ArithmeticException, or NumberFormatException for a zero.
    scaleRange,
    /// The quotient has more digits than the output buffer holds.
    capacity,
}

/// BigDecimal.unscaledValue() and scale(): the unscaled magnitude is `output[0 .. length]` followed by `zeros`
/// zeros, without leading zeros, and is empty for zero. BigDecimal has no negative zero.
struct DecimalBigParseValue
{
    bool negative;
    int scale;
    size_t length;
    size_t zeros;
}

/// Converts a parse result of kind bigDecimal as DecimalFormat.parse does: DigitList.getBigDecimal, an exact
/// division by the multiplier or, when it does not terminate, a division at the dividend's scale in `mode`,
/// then the negation. `digits` is the buffer the parse filled.
pure nothrow @nogc DecimalBigParseStatus parseBigDecimalValue(ref scope const DecimalParseResult result,
        scope const(char)[] digits, int multiplier, FixedRoundingMode mode, scope char[] output,
        out DecimalBigParseValue value)
in (result.kind == DecimalParseKind.bigDecimal && multiplier != 0)
{
    long scale;
    if (!dividendScale(result, scale))
        return DecimalBigParseStatus.scaleRange;
    const stored = digits[0 .. result.stored];
    const zeros = result.count - result.stored;
    // Java skips the division for a multiplier of one, which gives the same digits and scale here. The dividend is a nonnegative magnitude, so the quotient takes the multiplier's sign before the negation.
    const negativeQuotient = multiplier < 0;
    const ulong divisor = negativeQuotient ? -cast(long) multiplier : multiplier;
    // divide(BigDecimal) throws when the quotient does not terminate or its working scale overflows, and parse
    // then divides at the dividend's scale in the rounding mode.
    uint shift;
    if (!terminatingShift(remainderOf(stored, zeros, divisor), divisor, shift)
            || (stored.length != 0 && scale + workingScale(stored, divisor) > int.max))
        shift = 0;
    ulong remainder;
    if (!divideDigits(stored, zeros + shift, divisor, output, value, remainder))
        return DecimalBigParseStatus.capacity;
    if (remainder != 0)
    {
        if (mode == FixedRoundingMode.unnecessary)
            return DecimalBigParseStatus.inexact;
        if (roundsUp(remainder, output[0 .. value.length], divisor, negativeQuotient, mode)
                && !increment(output, value.length))
            return DecimalBigParseStatus.capacity;
    }
    value.negative = value.length != 0 && negativeQuotient == result.positive;
    value.scale = cast(int)(scale + shift);
    return DecimalBigParseStatus.complete;
}

private:

bool dividendScale(ref scope const DecimalParseResult result, out long scale) pure nothrow @nogc
{
    // new BigDecimal("0E" + decimalAt) rejects a scale outside the int range.
    if (result.count == 0)
    {
        scale = -cast(long) result.decimalAt;
        return scale <= int.max;
    }
    // scaleByPowerOfTen receives decimalAt - count in wrapped int arithmetic.
    const power = cast(int)(cast(uint) result.decimalAt - cast(uint) result.count);
    scale = -cast(long) power;
    return scale <= int.max;
}

ulong remainderOf(scope const(char)[] stored, size_t zeros, ulong divisor) pure nothrow @nogc
{
    ulong remainder;
    foreach (digit; stored)
        remainder = (remainder * 10 + (digit - '0')) % divisor;
    foreach (_; 0 .. zeros)
    {
        if (remainder == 0)
            break;
        remainder = remainder * 10 % divisor;
    }
    return remainder;
}

// The fewest appended zeros that make the dividend a multiple of the divisor. A divisor of at most 2^31 has at
// most 31 factors of two and 13 of five, so a terminating quotient needs at most 31.
bool terminatingShift(ulong remainder, ulong divisor, out uint shift) pure nothrow @nogc
{
    foreach (uint extra; 0 .. 32)
    {
        if (remainder == 0)
        {
            shift = extra;
            return true;
        }
        remainder = remainder * 10 % divisor;
    }
    return false;
}

// What divide(BigDecimal, MathContext) adds to the preferred scale before it rounds: the divisor's precision plus
// the extra precision ceil(10 * precision / 3) that divide(BigDecimal) requests, less one when the dividend's
// digits exceed the divisor's once both are normalized to [0.1, 1). Java's sum also subtracts and adds the
// dividend's precision (mcp = xprec + ceil(10 yprec / 3)); those two terms cancel.
long workingScale(scope const(char)[] stored, ulong divisor) pure nothrow @nogc
{
    char[10] text;
    size_t precision;
    for (ulong rest = divisor; rest != 0; rest /= 10)
        ++precision;
    ulong rest = divisor;
    foreach_reverse (ref digit; text[0 .. precision])
    {
        digit = cast(char)('0' + rest % 10);
        rest /= 10;
    }
    long added = precision + (10 * precision + 2) / 3;
    foreach (i; 0 .. stored.length > precision ? stored.length : precision)
    {
        const left = i < stored.length ? stored[i] : '0';
        const right = i < precision ? text[i] : '0';
        if (left != right)
            return left > right ? added - 1 : added;
    }
    return added;
}

// Long division of `stored` followed by `zeros` zeros into the quotient's length and zeros. Once the remainder is
// zero inside the zeros, the rest of the quotient is zeros and stays implicit.
pure nothrow @nogc bool divideDigits(scope const(char)[] stored, size_t zeros, ulong divisor,
        scope char[] output, ref DecimalBigParseValue quotient, out ulong remainder)
{
    foreach (digit; stored)
    {
        if (!emit(quotient, remainder, digit - '0', divisor, output))
            return false;
    }
    foreach (i; 0 .. zeros)
    {
        if (remainder == 0 && quotient.length != 0)
        {
            quotient.zeros = zeros - i;
            break;
        }
        if (!emit(quotient, remainder, 0, divisor, output))
            return false;
    }
    return true;
}

pure nothrow @nogc bool emit(ref DecimalBigParseValue quotient, ref ulong remainder, uint digit,
        ulong divisor, scope char[] output)
{
    const partial = remainder * 10 + digit;
    const next = partial / divisor;
    remainder = partial % divisor;
    if (next == 0 && quotient.length == 0)
        return true;
    if (quotient.length == output.length)
        return false;
    output[quotient.length++] = cast(char)('0' + next);
    return true;
}

// BigDecimal's rounding of a nonzero remainder: the comparison of twice the remainder with the divisor decides
// the half modes, and the quotient's own sign decides CEILING and FLOOR.
pure nothrow @nogc bool roundsUp(ulong remainder, scope const(char)[] quotient, ulong divisor,
        bool negative, FixedRoundingMode mode)
{
    // An if chain instead of a final switch, which would instantiate druntime's switch-error templates.
    if (mode == FixedRoundingMode.up)
        return true;
    if (mode == FixedRoundingMode.down || mode == FixedRoundingMode.unnecessary)
        return false;
    if (mode == FixedRoundingMode.ceiling)
        return !negative;
    if (mode == FixedRoundingMode.floor)
        return negative;
    const twice = remainder * 2;
    if (twice != divisor)
        return twice > divisor;
    if (mode == FixedRoundingMode.halfEven)
        return quotient.length != 0 && (quotient[$ - 1] & 1) == 1;
    return mode == FixedRoundingMode.halfUp;
}

bool increment(scope char[] output, ref size_t length) pure nothrow @nogc
{
    foreach_reverse (ref digit; output[0 .. length])
    {
        if (digit != '9')
        {
            ++digit;
            return true;
        }
        digit = '0';
    }
    // All nines, or a zero quotient: the carry adds a leading one, and the rest are already zeros.
    if (length == output.length)
        return false;
    output[length++] = '0';
    output[0] = '1';
    return true;
}
