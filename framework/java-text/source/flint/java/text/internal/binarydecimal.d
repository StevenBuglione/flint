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
    char[20] digits;
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

/// Converts the integral and signed-long paths without entering limb arithmetic.
bool tryBoundedBinaryDecimal(ulong bits, ref BinaryDecimal result) pure nothrow @nogc
{
    return tryBinaryDecimal(bits, false, result);
}

/// Converts finite binary64 values. Special values leave the result untouched.
bool tryFiniteBinaryDecimal(ulong bits, ref BinaryDecimal result) pure nothrow @nogc
{
    return tryBinaryDecimal(bits, true, result);
}

private bool tryBinaryDecimal(ulong bits, bool allowLimbs, ref BinaryDecimal result) pure nothrow @nogc
{
    import core.bitop : bsr;

    if (tryIntegerBinaryDecimal(bits, result))
        return true;
    const rawExponent = cast(int)((bits >> 52) & 0x7ff);
    if (rawExponent == 0x7ff || (rawExponent == 0 && !allowLimbs))
        return false;
    const fraction = bits & ((1UL << 52) - 1);
    const shift = rawExponent == 0 ? 52 - bsr(fraction) : 0;
    const significand = rawExponent == 0 ? fraction << shift : (1UL << 52) | fraction;
    const exponent = (rawExponent == 0 ? 1 - shift : rawExponent) - 1023;

    const scale = prepareScale(significand, exponent, 53 - shift);
    ScaledBinary scaled;
    BinaryDecimal converted;
    if (tryLongScale(scale, scaled))
        converted = developBoundedDigits(scaled);
    else if (!allowLimbs || !developGeneralDigits(scale, converted))
        return false;

    converted.negative = (bits >> 63) != 0;
    result = converted;
    return true;
}

private struct BinaryScale
{
    ulong significand;
    int width;
    int numeratorFives;
    int denominatorFives;
    int numeratorTwos;
    int denominatorTwos;
    int marginTwos;
    int decimalExponent;
}

private struct ScaledBinary
{
    long numerator;
    long denominator;
    long margin;
    int decimalExponent;
}

private BinaryScale prepareScale(ulong significand, int exponent, int significantBits) pure nothrow @nogc
{
    import core.bitop : bsf;

    const trailing = bsf(significand);
    const width = 53 - trailing;
    const fractionBits = width > exponent + 1 ? width - exponent - 1 : 0;
    const decimalExponent = estimateDecimalExponent(significand, exponent);
    const numeratorFives = decimalExponent < 0 ? -decimalExponent : 0;
    const denominatorFives = decimalExponent > 0 ? decimalExponent : 0;

    int numeratorTwos = numeratorFives + fractionBits + exponent;
    int denominatorTwos = denominatorFives + fractionBits;
    int marginTwos = numeratorTwos - significantBits;
    numeratorTwos -= width - 1;

    const commonTwos = numeratorTwos < denominatorTwos ? numeratorTwos : denominatorTwos;
    numeratorTwos -= commonTwos;
    denominatorTwos -= commonTwos;
    marginTwos -= commonTwos;
    if (width == 1)
        --marginTwos;
    if (marginTwos < 0)
    {
        numeratorTwos -= marginTwos;
        denominatorTwos -= marginTwos;
        marginTwos = 0;
    }
    return BinaryScale(significand >> trailing, width, numeratorFives, denominatorFives,
            numeratorTwos, denominatorTwos, marginTwos, decimalExponent);
}

private bool tryLongScale(ref scope const BinaryScale scale, out ScaledBinary scaled) pure nothrow @nogc
{
    // With 53 significant bits, width plus numeratorTwos is at least 54.
    // Subnormals need larger powers, so binary64 does not use the upstream int path.
    const numeratorBits = scale.width + scale.numeratorTwos + bitsForFivePower(scale.numeratorFives);
    const tenDenominatorBits = scale.denominatorTwos + 1 + bitsForFivePower(scale.denominatorFives + 1);
    if (numeratorBits >= 64 || tenDenominatorBits >= 64)
        return false;

    const numeratorPower = powersOfFive[scale.numeratorFives];
    scaled.numerator = (cast(long) scale.significand * numeratorPower) << scale.numeratorTwos;
    scaled.denominator = powersOfFive[scale.denominatorFives] << scale.denominatorTwos;
    scaled.margin = numeratorPower << scale.marginTwos;
    scaled.decimalExponent = scale.decimalExponent;
    return true;
}

private int estimateDecimalExponent(ulong significand, int exponent) pure nothrow @nogc
{
    const normalized = cast(double) significand * 0x1p-52;
    const estimate = (normalized - 1.5) * 0.289529654 + 0.176091259 + exponent * 0.301029995663981;
    const truncated = cast(int) estimate;
    return estimate < truncated ? truncated - 1 : truncated;
}

private BinaryDecimal developBoundedDigits(ScaledBinary scaled) pure nothrow @nogc
{
    BinaryDecimal result;
    long remainder = scaled.numerator;
    long margin = scaled.margin;
    const denominator = scaled.denominator;
    const tenDenominator = denominator * 10;
    int decimalExponent = scaled.decimalExponent;

    const leading = remainder / denominator;
    remainder = 10 * (remainder % denominator);
    margin *= 10;
    bool low = remainder < margin;
    bool high = remainder + margin > tenDenominator;
    if (leading == 0 && !high)
        --decimalExponent;
    else
        result.digits[result.count++] = cast(char)('0' + leading);

    // Java's compatible exponent notation emits at least two digits.
    if (decimalExponent < -3 || decimalExponent >= 8)
        low = high = false;
    while (!low && !high)
    {
        const digit = remainder / denominator;
        remainder = 10 * (remainder % denominator);
        margin *= 10;
        // The signed-long path stops when scaling the margin wraps out of its positive range.
        low = margin <= 0 || remainder < margin;
        high = margin <= 0 || remainder + margin > tenDenominator;
        result.digits[result.count++] = cast(char)('0' + digit);
    }

    result.decimalAt = decimalExponent + 1;
    result.exact = remainder == 0;
    const difference = (remainder << 1) - tenDenominator;
    if (high && (!low || difference > 0 || (difference == 0 && (result.digits[result.count - 1] & 1) != 0)))
        roundDigits(result);
    return result;
}

private struct GeneralScale
{
    import flint.java.internal.math.fdbiginteger : FDBigInteger;

    FDBigInteger remainder;
    FDBigInteger denominator;
    FDBigInteger margin;
    FDBigInteger tenDenominator;
}

private bool prepareGeneralScale(ref scope const BinaryScale scale, out GeneralScale operands) pure nothrow @nogc
{
    import flint.java.internal.math.fdbiginteger : FDBigInteger;

    return FDBigInteger.tryScale(scale.significand, scale.numeratorFives, scale.numeratorTwos,
            operands.remainder) && FDBigInteger.tryScale(1, scale.denominatorFives, scale.denominatorTwos,
            operands.denominator) && FDBigInteger.tryScale(1, scale.numeratorFives + 1,
            scale.marginTwos + 1, operands.margin) && FDBigInteger.tryScale(1,
            scale.denominatorFives + 1, scale.denominatorTwos + 1, operands.tenDenominator);
}

private bool developGeneralDigits(ref scope const BinaryScale scale, out BinaryDecimal result) pure nothrow @nogc
{
    GeneralScale operands;
    if (!prepareGeneralScale(scale, operands))
        return false;

    int decimalExponent = scale.decimalExponent;
    uint digit;
    if (!operands.remainder.tryQuoRemIteration(operands.denominator, digit))
        return false;
    bool low = operands.remainder.cmp(operands.margin) < 0;
    bool high = operands.tenDenominator.addAndCmp(operands.remainder, operands.margin) <= 0;
    if (digit == 0 && !high)
        --decimalExponent;
    else
        result.digits[result.count++] = cast(char)('0' + digit);

    if (decimalExponent < -3 || decimalExponent >= 8)
        low = high = false;
    while (!low && !high)
    {
        if (result.count == result.digits.length || !operands.remainder.tryQuoRemIteration(operands.denominator,
                digit) || !operands.margin.tryMultiplyBy10())
            return false;
        low = operands.remainder.cmp(operands.margin) < 0;
        high = operands.tenDenominator.addAndCmp(operands.remainder, operands.margin) <= 0;
        result.digits[result.count++] = cast(char)('0' + digit);
    }

    result.decimalAt = decimalExponent + 1;
    finishGeneralDigits(operands, result, low, high);
    return true;
}

private pure nothrow @nogc void finishGeneralDigits(ref scope const GeneralScale operands,
        ref BinaryDecimal result, bool low, bool high)
{
    import flint.java.internal.math.fdbiginteger : FDBigInteger;

    const zero = FDBigInteger.init;
    result.exact = operands.remainder.cmp(zero) == 0;
    if (high)
    {
        const difference = -operands.tenDenominator.addAndCmp(operands.remainder, operands.remainder);
        if (!low || difference > 0 || (difference == 0 && (result.digits[result.count - 1] & 1) != 0))
            roundDigits(result);
    }
}

private void roundDigits(ref BinaryDecimal result) pure nothrow @nogc
{
    foreach_reverse (index; 0 .. result.count)
    {
        if (result.digits[index] != '9')
        {
            ++result.digits[index];
            result.roundedUp = true;
            return;
        }
        result.digits[index] = '0';
    }
    result.digits[0] = '1';
    ++result.decimalAt;
}

private int bitsForFivePower(int exponent) pure nothrow @nogc
{
    return exponent < fivePowerBits.length ? fivePowerBits[exponent] : exponent * 3;
}

private static immutable long[27] powersOfFive = [
    1, 5, 25, 125, 625, 3_125, 15_625, 78_125, 390_625, 1_953_125, 9_765_625, 48_828_125,
    244_140_625, 1_220_703_125, 6_103_515_625, 30_517_578_125, 152_587_890_625, 762_939_453_125,
    3_814_697_265_625, 19_073_486_328_125, 95_367_431_640_625, 476_837_158_203_125,
    2_384_185_791_015_625, 11_920_928_955_078_125, 59_604_644_775_390_625,
    298_023_223_876_953_125, 1_490_116_119_384_765_625,
];

private static immutable int[27] fivePowerBits = [
    0, 3, 5, 7, 10, 12, 14, 17, 19, 21, 24, 26, 28, 31, 33, 35, 38, 40, 42, 45, 47, 49, 52, 54, 56, 59,
    61,
];
