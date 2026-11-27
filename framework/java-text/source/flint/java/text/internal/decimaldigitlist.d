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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/text/DigitList.java
// Modified by the Flint authors.
module flint.java.text.internal.decimaldigitlist;

import flint.java.text.internal.binarydecimal : BinaryDecimal;

@safe:

package(flint.java.text):

enum FixedRoundingMode : ubyte
{
    up,
    down,
    ceiling,
    floor,
    halfEven,
    halfUp,
    halfDown,
    unnecessary,
}

enum FixedRoundingStatus : ubyte
{
    complete,
    inexact,
}

/// Converts finite binary64 values to the fixed-point DigitList representation.
pure nothrow @nogc bool tryFixedBinaryDecimal(ulong bits, uint maximumFractionDigits,
        ref BinaryDecimal result, FixedRoundingMode mode = FixedRoundingMode.halfEven)
{
    FixedRoundingStatus status;
    return tryFixedBinaryDecimal(bits, maximumFractionDigits, result, mode, status)
        && status == FixedRoundingStatus.complete;
}

pure nothrow @nogc bool tryFixedBinaryDecimal(ulong bits, uint maximumFractionDigits,
        ref BinaryDecimal result, FixedRoundingMode mode, out FixedRoundingStatus status)
{
    BinaryDecimal converted;
    if (!tryDigitListDecimal(bits, converted))
        return false;
    converted.count = roundFixed(converted.digits[0 .. converted.count], converted.decimalAt,
            maximumFractionDigits, converted.roundedUp, converted.exact, converted.negative, mode, status);
    result = converted;
    return true;
}

/// Rounds normalized binary64 decimal digits in place and returns the retained digit count.
/// `decimalAt` is the count of positions before the decimal point, possibly negative.
/// `roundedUp` and `exact` describe the binary-to-decimal conversion, before formatting.
pure nothrow @nogc size_t roundFixed(scope char[] digits, ref int decimalAt, uint maximumFractionDigits,
        bool roundedUp, bool exact, FixedRoundingMode mode = FixedRoundingMode.halfEven)
{
    FixedRoundingStatus status;
    return roundFixed(digits, decimalAt, maximumFractionDigits, roundedUp, exact, false, mode, status);
}

pure nothrow @nogc size_t roundFixed(scope char[] digits, ref int decimalAt, uint maximumFractionDigits,
        bool roundedUp, bool exact, bool negative, FixedRoundingMode mode, out FixedRoundingStatus status)
{
    status = FixedRoundingStatus.complete;
    const retained = cast(long) decimalAt + maximumFractionDigits;
    if (retained < 0)
        return 0;
    // DigitList checks the zero-retained boundary before stripping trailing zero digits.
    if (retained != 0)
        digits = digits[0 .. withoutTrailingZeros(digits)];
    if (cast(ulong) retained >= digits.length)
        return digits.length;
    return roundAt(digits, decimalAt, cast(size_t) retained, roundedUp, exact, negative, mode, status);
}

/// Converts finite binary64 values to the exponential DigitList representation.
pure nothrow @nogc bool trySignificantBinaryDecimal(ulong bits, uint maximumDigits,
        ref BinaryDecimal result, FixedRoundingMode mode, out FixedRoundingStatus status)
{
    BinaryDecimal converted;
    if (!tryDigitListDecimal(bits, converted))
        return false;
    converted.count = roundSignificant(converted.digits[0 .. converted.count], converted.decimalAt,
            maximumDigits, converted.roundedUp, converted.exact, converted.negative, mode, status);
    result = converted;
    return true;
}

/// Rounds to at most `maximumDigits` significant digits, as DigitList does for exponential patterns.
/// Trailing zeros are always removed. A long keeps every digit at zero maximum digits, so it passes uint.max.
pure nothrow @nogc size_t roundSignificant(scope char[] digits, ref int decimalAt, uint maximumDigits,
        bool roundedUp, bool exact, bool negative, FixedRoundingMode mode, out FixedRoundingStatus status)
{
    status = FixedRoundingStatus.complete;
    digits = digits[0 .. withoutTrailingZeros(digits)];
    if (maximumDigits >= digits.length)
        return digits.length;
    return roundAt(digits, decimalAt, maximumDigits, roundedUp, exact, negative, mode, status);
}

// `keep` is below the digit count. Only a fixed-point call retaining zero digits keeps trailing zeros.
private pure nothrow @nogc size_t roundAt(scope char[] digits, ref int decimalAt, size_t keep,
        bool roundedUp, bool exact, bool negative, FixedRoundingMode mode, ref FixedRoundingStatus status)
{
    if (mode == FixedRoundingMode.unnecessary)
    {
        status = FixedRoundingStatus.inexact;
        return withoutTrailingZeros(digits[0 .. keep]);
    }
    if (!roundsUp(digits, keep, roundedUp, exact, negative, mode))
        return withoutTrailingZeros(digits[0 .. keep]);

    foreach_reverse (index; 0 .. keep)
    {
        if (digits[index] != '9')
        {
            ++digits[index];
            return index + 1;
        }
    }
    digits[0] = '1';
    ++decimalAt;
    return 1;
}

private bool tryDigitListDecimal(ulong bits, out BinaryDecimal converted) pure nothrow @nogc
{
    import flint.java.text.internal.binarydecimal : tryFiniteBinaryDecimal;

    if (!tryFiniteBinaryDecimal(bits, converted))
        return false;
    // FloatingDecimal emits one zero digit. DigitList keeps only its separate sign.
    if (converted.count == 1 && converted.digits[0] == '0')
        converted.count = 0;
    return true;
}

private size_t withoutTrailingZeros(scope const(char)[] digits) pure nothrow @nogc
{
    size_t length = digits.length;
    while (length > 1 && digits[length - 1] == '0')
        --length;
    return length;
}

private pure nothrow @nogc bool roundsUp(scope const(char)[] digits, size_t keep, bool roundedUp,
        bool exact, bool negative, FixedRoundingMode mode)
{
    if (mode <= FixedRoundingMode.floor)
        return directedRoundsUp(negative, mode);
    if (mode == FixedRoundingMode.unnecessary)
        return false;
    return halfRoundsUp(digits, keep, roundedUp, exact, mode);
}

private pure nothrow @nogc bool directedRoundsUp(bool negative, FixedRoundingMode mode)
{
    if (mode == FixedRoundingMode.up)
        return true;
    if (mode == FixedRoundingMode.down)
        return false;
    return mode == FixedRoundingMode.ceiling ? !negative : negative;
}

private pure nothrow @nogc bool halfRoundsUp(scope const(char)[] digits, size_t keep, bool roundedUp,
        bool exact, FixedRoundingMode mode)
{
    const firstDiscarded = digits[keep];
    if (firstDiscarded != '5')
        return firstDiscarded > '5';
    if (keep + 1 == digits.length)
    {
        if (mode != FixedRoundingMode.halfEven)
            return exact ? mode == FixedRoundingMode.halfUp : !roundedUp;
        if (roundedUp)
            return false;
        return !exact || (keep != 0 && (digits[keep - 1] & 1) != 0);
    }
    // At zero retained digits Java consults the untrimmed producer sequence.
    if (mode != FixedRoundingMode.halfEven)
        return true;
    foreach (digit; digits[keep + 1 .. $])
        if (digit != '0')
            return true;
    return false;
}
