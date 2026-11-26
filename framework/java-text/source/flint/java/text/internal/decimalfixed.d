// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Fixed-point rendering for resolved DecimalFormat patterns.
module flint.java.text.internal.decimalfixed;

import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData;

@safe:

package(flint.java.text):

struct DecimalAffixes
{
    string prefix;
    string suffix;
}

struct DecimalFixedPattern
{
    DecimalAffixes positive;
    DecimalAffixes negative = DecimalAffixes("-", null);
    uint minimumIntegerDigits = 1;
    uint minimumFractionDigits;
    uint maximumFractionDigits = 3;
    uint groupingSize;
    // A percent pattern adds two decimal places, and a per-mille pattern adds three.
    ubyte scale;
    bool decimalSeparatorAlwaysShown;
}

/// Writes using the ASCII numeric symbols of the explicit ROOT and English profiles.
/// Returns the required byte count and leaves a short buffer untouched.
size_t renderDecimalLong(long value, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output) pure nothrow @nogc
{
    const negative = value < 0;
    ulong magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    char[20] digits;
    size_t start = digits.length;
    while (magnitude != 0)
    {
        digits[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }

    const decimalAt = value == 0 ? 0 : cast(int)(digits.length - start + pattern.scale);
    return renderFixedDigits(digits[start .. $], decimalAt, negative, pattern, symbols, output);
}

/// Renders finite binary64 through the general fixed-point path using the explicit Latin symbols.
/// A successful call reports bytes required. A short buffer or unsupported value is untouched.
pure nothrow @nogc bool tryRenderDecimalDouble(ulong bits, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output, out size_t required)
{
    import flint.java.text.internal.binarydecimal : BinaryDecimal;
    import flint.java.text.internal.decimaldigitlist : tryFixedBinaryDecimal;

    if (pattern.scale != 0 || usesGroupedFastPath(bits, pattern))
        return false;

    // These are the floating-point limits of Java's DecimalFormat, independent of long padding.
    scope DecimalFixedPattern effective = pattern;
    if (effective.minimumIntegerDigits > 309)
        effective.minimumIntegerDigits = 309;
    if (effective.minimumFractionDigits > 340)
        effective.minimumFractionDigits = 340;
    if (effective.maximumFractionDigits > 340)
        effective.maximumFractionDigits = 340;

    BinaryDecimal converted;
    if (!tryFixedBinaryDecimal(bits, effective.maximumFractionDigits, converted))
        return false;

    const decimalAt = converted.count != 0 ? converted.decimalAt : 0;
    required = renderFixedDigits(converted.digits[0 .. converted.count], decimalAt,
            converted.negative, effective, symbols, output);
    return true;
}

private bool usesGroupedFastPath(ulong bits, ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
{
    const magnitudeBits = bits & (ulong.max >> 1);
    // 0x41df... is the binary64 representation of Integer.MAX_VALUE.
    return magnitudeBits <= 0x41df_ffff_ffc0_0000 && pattern.groupingSize == 3 && pattern.minimumIntegerDigits == 1
        && pattern.minimumFractionDigits == 0 && pattern.maximumFractionDigits == 3
        && !pattern.decimalSeparatorAlwaysShown;
}

private pure nothrow @nogc size_t renderFixedDigits(scope const(char)[] digits, int decimalAt, bool negative,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols, scope char[] output)
{
    const affixes = negative ? pattern.negative : pattern.positive;
    const integralDigits = decimalAt > 0 ? cast(size_t) decimalAt : 0;
    const visibleFraction = cast(int) digits.length - decimalAt;
    const fractionDigits = visibleFraction > 0 ? cast(size_t) visibleFraction : 0;
    const fractionCount = fractionDigits > pattern.minimumFractionDigits ? fractionDigits : pattern
        .minimumFractionDigits;
    size_t integerCount = integralDigits > pattern.minimumIntegerDigits ? integralDigits : pattern.minimumIntegerDigits;
    if (integerCount == 0 && fractionCount == 0)
        integerCount = 1;
    const groups = integerCount && pattern.groupingSize ? (integerCount - 1) / pattern.groupingSize : 0;
    const decimalPoint = fractionCount != 0 || pattern.decimalSeparatorAlwaysShown;
    const required = cast(ulong) affixes.prefix.length + integerCount + groups + decimalPoint
        + fractionCount + affixes.suffix.length;
    if (required > output.length)
        return required > size_t.max ? size_t.max : cast(size_t) required;

    const prefixEnd = affixes.prefix.length;
    output[0 .. prefixEnd] = affixes.prefix;
    size_t at = prefixEnd + integerCount + groups;
    writeInteger(digits, integerCount - integralDigits, integerCount, pattern.groupingSize, symbols,
            output[prefixEnd .. at]);
    if (decimalPoint)
        output[at++] = cast(char) symbols.decimalSeparator;
    writeFraction(digits, decimalAt, cast(char) symbols.zeroDigit, output[at .. at + fractionCount]);
    output[at + fractionCount .. cast(size_t) required] = affixes.suffix;
    return cast(size_t) required;
}

private void writeFraction(scope const(char)[] digits, int point, char zero, scope char[] output) pure nothrow @nogc
{
    foreach (position, ref digit; output)
    {
        const index = cast(long) position + point;
        digit = index >= 0 && index < digits.length ? digits[cast(size_t) index] : zero;
    }
}

private void writeInteger(scope const(char)[] digits, size_t padding, size_t integerCount,
        uint groupingSize, ref scope const DecimalSymbolData symbols, scope char[] output) pure nothrow @nogc
{
    size_t at;
    foreach (i; 0 .. integerCount)
    {
        if (i != 0 && groupingSize && (integerCount - i) % groupingSize == 0)
            output[at++] = cast(char) symbols.groupingSeparator;
        if (i >= padding && i - padding < digits.length)
            output[at++] = digits[i - padding];
        else
            output[at++] = cast(char) symbols.zeroDigit;
    }
}
