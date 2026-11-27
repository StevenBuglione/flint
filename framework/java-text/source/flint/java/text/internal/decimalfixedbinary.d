// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Binary64 conversion for resolved fixed-point DecimalFormat patterns.
module flint.java.text.internal.decimalfixedbinary;

import flint.java.text.internal.decimalfixed : DecimalAffixes, DecimalFixedPattern,
    multiplyUnsignedWord, primitiveFractionWidth, renderFixedDigits, writeUnsignedDigits;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;

@safe:

package(flint.java.text):

/// Uses the multiplier implied by the fixed-point pattern.
pure nothrow @nogc bool tryRenderDecimalDouble(ulong bits, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols,
        scope char[] output, out size_t required, FixedRoundingMode mode = FixedRoundingMode.halfEven)
{
    FixedRoundingStatus status;
    return tryRenderDecimalDouble(bits, pattern, symbols, output, required, mode, status)
        && status == FixedRoundingStatus.complete;
}

pure nothrow @nogc bool tryRenderDecimalDouble(ulong bits, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols,
        scope char[] output, out size_t required, FixedRoundingMode mode, out FixedRoundingStatus status)
{
    if (pattern.scale != 0 && pattern.scale != 2 && pattern.scale != 3)
        return false;
    const multiplier = pattern.scale == 0 ? 1 : (pattern.scale == 2 ? 100 : 1000);
    return tryRenderDecimalDouble(bits, multiplier, pattern, symbols, output, required, mode, status);
}

/// Uses a resolved Java multiplier while preserving the pattern's affixes.
/// A successful call reports bytes required. A short buffer or unsupported value is untouched.
pure nothrow @nogc bool tryRenderDecimalDouble(ulong bits, int multiplier, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output, out size_t required,
        FixedRoundingMode mode = FixedRoundingMode.halfEven)
{
    FixedRoundingStatus status;
    return tryRenderDecimalDouble(bits, multiplier, pattern, symbols, output, required, mode, status)
        && status == FixedRoundingStatus.complete;
}

pure nothrow @nogc bool tryRenderDecimalDouble(ulong bits, int multiplier, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output, out size_t required,
        FixedRoundingMode mode, out FixedRoundingStatus status)
{
    import flint.java.text.internal.binarydecimal : BinaryDecimal;
    import flint.java.text.internal.decimaldigitlist : tryFixedBinaryDecimal;

    status = FixedRoundingStatus.complete;
    required = 0;
    if (multiplier != 1)
        bits = scaleBinary(bits, multiplier);
    else if (mode == FixedRoundingMode.halfEven && usesGroupedFastPath(bits, pattern))
    {
        required = renderGroupedFast(bits, pattern, symbols, output);
        return true;
    }

    if ((bits & (ulong.max >> 1)) >= infinityBits)
    {
        required = renderSpecial(bits, pattern, symbols, output);
        return true;
    }

    BinaryDecimal converted;
    if (!tryFixedBinaryDecimal(bits, primitiveFractionWidth(pattern.maximumFractionDigits), converted, mode, status))
        return false;
    if (status == FixedRoundingStatus.inexact)
        return true;

    const decimalAt = converted.count != 0 ? converted.decimalAt : 0;
    required = renderFixedDigits(converted.digits[0 .. converted.count], decimalAt,
            converted.negative, pattern, symbols, output);
    return true;
}

private enum ulong implicitBit = 1UL << 52;
private enum ulong signBit = 1UL << 63;
private enum ulong infinityBits = 0x7ff0_0000_0000_0000;

private ulong scaleBinary(ulong bits, int multiplier) pure nothrow @nogc
{
    const magnitude = bits & (signBit - 1);
    if (magnitude > infinityBits)
        return bits;
    const negativeMultiplier = multiplier < 0;
    const sign = (bits & signBit) ^ (negativeMultiplier ? signBit : 0);
    if (multiplier == 0)
        return magnitude == infinityBits ? infinityBits | (implicitBit >> 1) : sign;
    if (magnitude == 0 || magnitude == infinityBits)
        return sign | magnitude;

    const factor = negativeMultiplier ? -cast(uint) multiplier : cast(uint) multiplier;
    return scaleFiniteBinary(magnitude, sign, factor);
}

private ulong scaleFiniteBinary(ulong magnitude, ulong sign, uint factor) pure nothrow @nogc
{
    import core.bitop : bsr;

    const exponent = cast(uint)(magnitude >> 52);
    const significand = binarySignificand(magnitude, exponent);
    ulong product;
    uint upper;
    if (factor <= 1023)
        product = significand * factor;
    else
        product = multiplyUnsignedWord(significand, factor, upper);
    if (upper == 0 && product < implicitBit)
        return sign | product;

    const discarded = upper == 0 ? cast(uint)(bsr(product) - 52) : cast(uint)(bsr(cast(ulong) upper) + 12);
    ulong rounded = roundSignificandRight(product, discarded);
    // Any upper contribution is even after the shift, so the low word decides ties.
    if (upper != 0)
        rounded += cast(ulong) upper << (64 - discarded);
    uint outputExponent = (exponent == 0 ? 1u : exponent) + discarded;
    if (rounded == (implicitBit << 1))
    {
        rounded >>= 1;
        ++outputExponent;
    }
    if (outputExponent >= 0x7ff)
        return sign | infinityBits;
    return sign | (cast(ulong) outputExponent << 52) | (rounded & (implicitBit - 1));
}

private ulong binarySignificand(ulong magnitude, uint exponent) pure nothrow @nogc
{
    const fraction = magnitude & (implicitBit - 1);
    return exponent == 0 ? fraction : fraction | implicitBit;
}

// Only the grouped path requests shifts of 64 or more, with a product of at most 63 bits.
private ulong roundSignificandRight(ulong product, uint discarded) pure nothrow @nogc
{
    if (discarded == 0)
        return product;
    if (discarded >= 64)
        return 0;
    const rounded = product >> discarded;
    const halfway = 1UL << (discarded - 1);
    const remainder = product & ((1UL << discarded) - 1);
    return rounded + (remainder > halfway || (remainder == halfway && (rounded & 1) != 0));
}

private pure nothrow @nogc size_t renderGroupedFast(ulong bits,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols, scope char[] output)
{
    const magnitude = bits & (signBit - 1);
    const exponent = cast(uint)(magnitude >> 52);
    const product = binarySignificand(magnitude, exponent) * 1000;
    // Round directly to integer thousandths to avoid rounding a binary64 intermediate.
    const discarded = 1075u - (exponent == 0 ? 1u : exponent);
    const units = roundSignificandRight(product, discarded);

    char[20] digits;
    const start = writeUnsignedDigits(units, digits);
    const decimalAt = units == 0 ? 0 : cast(int)(digits.length - start) - 3;
    size_t end = digits.length;
    while (end > start && digits[end - 1] == '0')
        --end;
    return renderFixedDigits(digits[start .. end], decimalAt, (bits & signBit) != 0, pattern, symbols, output);
}

private pure nothrow @nogc size_t renderSpecial(ulong bits, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output)
{
    const infinity = (bits & (ulong.max >> 1)) == infinityBits;
    const token = infinity ? symbols.infinity : symbols.nan;
    const affixes = infinity ? ((bits >> 63) != 0 ? pattern.negative : pattern.positive) : DecimalAffixes.init;
    const required = cast(ulong) affixes.prefix.length + token.length + affixes.suffix.length;
    if (required > output.length)
        return required > size_t.max ? size_t.max : cast(size_t) required;

    const tokenStart = affixes.prefix.length;
    const tokenEnd = tokenStart + token.length;
    output[0 .. tokenStart] = affixes.prefix;
    output[tokenStart .. tokenEnd] = token;
    output[tokenEnd .. cast(size_t) required] = affixes.suffix;
    return cast(size_t) required;
}

private bool usesGroupedFastPath(ulong bits, ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
{
    const magnitudeBits = bits & (ulong.max >> 1);
    // 0x41df... is the binary64 representation of Integer.MAX_VALUE.
    return magnitudeBits <= 0x41df_ffff_ffc0_0000 && pattern.groupingSize == 3 && pattern.minimumIntegerDigits == 1
        && pattern.maximumIntegerDigits >= 10 && pattern.minimumFractionDigits == 0
        && pattern.maximumFractionDigits == 3 && !pattern.decimalSeparatorAlwaysShown;
}
