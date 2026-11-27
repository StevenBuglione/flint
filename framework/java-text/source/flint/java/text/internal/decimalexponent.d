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
// (subformatNumber, exponential branch, and format(long) through DigitList.set(long, maximumDigits)).
// Modified by the Flint authors.
/// Exponential rendering for resolved DecimalFormat patterns.
module flint.java.text.internal.decimalexponent;

import flint.java.text.internal.decimalfixed : DecimalFixedPattern, multiplyUnsignedWord,
    primitiveFractionWidth, writeWideUnsignedDigits;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus, roundSignificant;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;

@safe:

package(flint.java.text):

/// Formats an exact signed long product with significant-digit rounding.
/// Returns the required byte count, leaves a short buffer untouched and writes nothing when inexact.
pure nothrow @nogc size_t renderExponentLong(long value, int multiplier, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output, FixedRoundingMode mode,
        out FixedRoundingStatus status)
in (pattern.minimumExponentDigits != 0)
{
    const negativeValue = value < 0;
    const negativeMultiplier = multiplier < 0;
    const magnitude = negativeValue ? -cast(ulong) value : cast(ulong) value;
    const factor = negativeMultiplier ? -cast(uint) multiplier : cast(uint) multiplier;
    uint upper;
    const lower = multiplyUnsignedWord(magnitude, factor, upper);

    char[29] digits;
    const start = writeWideUnsignedDigits(lower, upper, digits);
    int decimalAt = cast(int)(digits.length - start);
    const negative = decimalAt != 0 && negativeValue != negativeMultiplier;
    // DigitList.set(long, 0) keeps every digit; only a positive digit limit rounds.
    const maximumDigits = significantLimit(pattern);
    const limit = maximumDigits == 0 ? uint.max : maximumDigits;
    const count = roundSignificant(digits[start .. $], decimalAt, limit, false, true, negative, mode, status);
    if (status == FixedRoundingStatus.inexact)
        return 0;
    return renderExponentDigits(digits[start .. start + count], decimalAt, negative, pattern, symbols, output);
}

/// The total digit limit for exponential DigitList rounding, after the primitive width caps.
uint significantLimit(ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
{
    return primitiveIntegerWidth(pattern.maximumIntegerDigits) + primitiveFractionWidth(pattern.maximumFractionDigits);
}

/// Writes rounded significant digits in exponential notation with the pattern's affixes.
/// Returns the required byte count and leaves a short buffer untouched.
pure nothrow @nogc size_t renderExponentDigits(scope const(char)[] digits, int decimalAt, bool negative,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols, scope char[] output)
{
    const layout = ExponentLayout(digits.length, digits.length == 0 ? 0 : decimalAt, pattern);
    const affixes = negative ? pattern.negative : pattern.positive;
    char[10] exponentDigits;
    const exponentStart = writeExponent(layout.exponent, exponentDigits);
    const exponentWidth = exponentDigits.length - exponentStart;
    const padding = pattern.minimumExponentDigits > exponentWidth ? pattern.minimumExponentDigits - exponentWidth : 0;
    const required = cast(ulong) affixes.prefix.length + layout.totalDigits + layout.decimalPoint
        + symbols.exponentSeparator.length + (layout.exponent < 0) + padding + exponentWidth + affixes.suffix.length;
    if (required > output.length)
        return required > size_t.max ? size_t.max : cast(size_t) required;

    size_t at = affixes.prefix.length;
    output[0 .. at] = affixes.prefix;
    const zero = cast(char) symbols.zeroDigit;
    foreach (i; 0 .. layout.totalDigits)
    {
        if (i == layout.integerDigits)
            output[at++] = cast(char) symbols.decimalSeparator;
        output[at++] = i < digits.length ? digits[i] : zero;
    }
    if (layout.decimalPoint && layout.totalDigits == layout.integerDigits)
        output[at++] = cast(char) symbols.decimalSeparator;
    output[at .. at + symbols.exponentSeparator.length] = symbols.exponentSeparator;
    at += symbols.exponentSeparator.length;
    if (layout.exponent < 0)
        output[at++] = cast(char) symbols.minusSign;
    output[at .. at + padding] = zero;
    at += padding;
    output[at .. at + exponentWidth] = exponentDigits[exponentStart .. $];
    output[at + exponentWidth .. cast(size_t) required] = affixes.suffix;
    return cast(size_t) required;
}

private:

struct ExponentLayout
{
    int exponent;
    size_t integerDigits;
    size_t totalDigits;
    bool decimalPoint;

    // Zero digits stand for zero, whose decimal position the caller has normalized to zero.
    this(size_t count, int decimalAt, ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
    {
        const repeat = primitiveIntegerWidth(pattern.maximumIntegerDigits);
        const minimumInteger = primitiveIntegerWidth(pattern.minimumIntegerDigits);
        // A repeating range wider than the minimum gives engineering notation, which ignores the minimum.
        const repeating = repeat > 1 && repeat > minimumInteger;
        if (repeating)
            exponent = repeatedExponent(decimalAt, cast(int) repeat);
        else
            exponent = decimalAt - cast(int) minimumInteger;
        if (count == 0)
            integerDigits = repeating ? 1 : minimumInteger;
        else
            integerDigits = cast(size_t)(decimalAt - exponent);
        size_t minimumDigits = minimumInteger + primitiveFractionWidth(pattern.minimumFractionDigits);
        if (minimumDigits < integerDigits)
            minimumDigits = integerDigits;
        totalDigits = count > minimumDigits ? count : minimumDigits;
        decimalPoint = integerDigits < totalDigits || pattern.decimalSeparatorAlwaysShown;
        // Java forces the zero exponent only after it has sized the integer digits.
        if (count == 0)
            exponent = 0;
    }
}

// For a repeat of 3: decimal positions 6,5,4 => 3; 3,2,1 => 0; 0,-1,-2 => -3. Division truncates like Java.
int repeatedExponent(int decimalAt, int repeat) pure nothrow @nogc
{
    if (decimalAt >= 1)
        return ((decimalAt - 1) / repeat) * repeat;
    return ((decimalAt - repeat) / repeat) * repeat;
}

size_t writeExponent(int exponent, ref scope char[10] digits) pure nothrow @nogc
{
    uint magnitude = exponent < 0 ? -cast(uint) exponent : cast(uint) exponent;
    size_t start = digits.length;
    while (magnitude != 0)
    {
        digits[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    return start;
}

uint primitiveIntegerWidth(uint width) pure nothrow @nogc
{
    enum limit = 309;
    return width < limit ? width : limit;
}
