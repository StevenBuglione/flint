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

// Ported from openjdk 21.0.13: src/java.base/share/classes/jdk/internal/math/FloatingDecimal.java
// Modified by the Flint authors.
module flint.java.text.internal.binarydecimal;

@safe:

package(flint.java.text):

/// The sign, significant digits, decimal point and conversion flags produced by FloatingDecimal.
struct BinaryDecimal
{
    char[19] digits;
    size_t count;
    int decimalAt;
    bool negative;
    bool roundedUp;
    bool exact;
}

/// Converts binary64 zeros and the integral fast path, with an unbiased exponent at most 62.
/// Returns false without modifying `result` when the general conversion is needed.
bool tryIntegerBinaryDecimal(ulong bits, ref BinaryDecimal result) pure nothrow @nogc
{
    enum signBit = 1UL << 63;
    enum implicitBit = 1UL << 52;

    const magnitude = bits & (signBit - 1);
    const negative = (bits & signBit) != 0;
    if (magnitude == 0)
    {
        result = BinaryDecimal.init;
        result.digits[0] = '0';
        result.count = 1;
        result.negative = negative;
        return true;
    }

    const exponent = cast(int)(magnitude >> 52) - 1023;
    if (exponent < 0 || exponent > 62)
        return false;
    const significand = implicitBit | (magnitude & (implicitBit - 1));
    ulong whole;
    if (exponent >= 52)
        whole = significand << (exponent - 52);
    else
    {
        const fractionBits = 52 - exponent;
        if ((significand & ((1UL << fractionBits) - 1)) != 0)
            return false;
        whole = significand >> fractionBits;
    }

    result = developIntegerDigits(whole, exponent);
    result.negative = negative;
    return true;
}

private BinaryDecimal developIntegerDigits(ulong whole, int exponent) pure nothrow @nogc
{
    BinaryDecimal result;
    // FloatingDecimal counts the decimal digits of 2^(binExp - 54) that may be discarded.
    if (exponent > 55)
    {
        const insignificant = 1UL << (exponent - 54);
        ulong scale = 1;
        while (insignificant >= scale * 10)
        {
            scale *= 10;
            ++result.decimalAt;
        }
        if (scale != 1)
        {
            const roundUp = whole % scale >= scale / 2;
            whole = whole / scale + roundUp;
        }
    }

    while (whole % 10 == 0)
    {
        whole /= 10;
        ++result.decimalAt;
    }

    char[19] digits;
    size_t first = digits.length;
    do
    {
        digits[--first] = cast(char)('0' + whole % 10);
        whole /= 10;
    }
    while (whole != 0);
    result.count = digits.length - first;
    result.digits[0 .. result.count] = digits[first .. $];
    result.decimalAt += cast(int) result.count;
    // The pinned integral conversion leaves both conversion flags false.
    return result;
}
