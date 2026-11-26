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
    uint maximumIntegerDigits = int.max;
    uint minimumFractionDigits;
    uint maximumFractionDigits = 3;
    uint groupingSize;
    // A percent pattern adds two decimal places, and a per-mille pattern adds three.
    ubyte scale;
    bool decimalSeparatorAlwaysShown;

    void setMinimumIntegerDigits(int width) pure nothrow @nogc
    {
        minimumIntegerDigits = width < 0 ? 0 : cast(uint) width;
        if (maximumIntegerDigits < minimumIntegerDigits)
            maximumIntegerDigits = minimumIntegerDigits;
    }

    void setMaximumIntegerDigits(int width) pure nothrow @nogc
    {
        maximumIntegerDigits = width < 0 ? 0 : cast(uint) width;
        if (minimumIntegerDigits > maximumIntegerDigits)
            minimumIntegerDigits = maximumIntegerDigits;
    }
}

/// Writes using the ASCII numeric symbols of the explicit ROOT and English profiles.
/// Returns the required byte count and leaves a short buffer untouched.
size_t renderDecimalLong(long value, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output) pure nothrow @nogc
{
    const negative = value < 0;
    ulong magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    char[20] digits;
    const start = writeUnsignedDigits(magnitude, digits);
    const decimalAt = value == 0 ? 0 : cast(int)(digits.length - start + pattern.scale);
    return renderFixedDigits(digits[start .. $], decimalAt, negative, pattern, symbols, output);
}

/// Formats an exact signed long product with the explicit Java multiplier and the pattern's affixes.
size_t renderDecimalLong(long value, int multiplier, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output) pure nothrow @nogc
{
    const negativeValue = value < 0;
    const negativeMultiplier = multiplier < 0;
    const magnitude = negativeValue ? -cast(ulong) value : cast(ulong) value;
    const factor = negativeMultiplier ? -cast(uint) multiplier : cast(uint) multiplier;
    uint upper;
    const lower = multiplyUnsignedWord(magnitude, factor, upper);

    char[29] digits;
    const start = writeWideUnsignedDigits(lower, upper, digits);
    const count = cast(int)(digits.length - start);
    const negative = count != 0 && negativeValue != negativeMultiplier;
    return renderFixedDigits(digits[start .. $], count, negative, pattern, symbols, output);
}

// The carry from adding the low 64 bits belongs in the high 32-bit word.
ulong multiplyUnsignedWord(ulong magnitude, uint factor, out uint upper) pure nothrow @nogc
{
    const lowerProduct = (magnitude & uint.max) * factor;
    const upperProduct = (magnitude >> 32) * factor;
    const lower = lowerProduct + (upperProduct << 32);
    upper = cast(uint)(upperProduct >> 32) + (lower < lowerProduct);
    return lower;
}

private size_t writeWideUnsignedDigits(ulong lower, uint upper, ref scope char[29] digits) pure nothrow @nogc
{
    size_t end = digits.length;
    while (upper != 0)
    {
        // Divide the upper 64 bits first and carry their remainder into the low 32 bits.
        const leading = (cast(ulong) upper << 32) | (lower >> 32);
        const quotient = leading / 10;
        const trailing = ((leading % 10) << 32) | (lower & uint.max);
        upper = cast(uint)(quotient >> 32);
        lower = (quotient << 32) | (trailing / 10);
        digits[--end] = cast(char)('0' + trailing % 10);
    }
    return writeUnsignedDigits(lower, digits[0 .. end]);
}

size_t writeUnsignedDigits(ulong magnitude, scope char[] digits) pure nothrow @nogc
{
    size_t start = digits.length;
    while (magnitude != 0)
    {
        digits[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    return start;
}

pure nothrow @nogc size_t renderFixedDigits(scope const(char)[] digits, int decimalAt, bool negative,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols, scope char[] output)
{
    const affixes = negative ? pattern.negative : pattern.positive;
    const integralDigits = decimalAt > 0 ? cast(size_t) decimalAt : 0;
    const visibleFraction = cast(int) digits.length - decimalAt;
    const fractionDigits = visibleFraction > 0 ? cast(size_t) visibleFraction : 0;
    const fractionCount = fractionDigits > pattern.minimumFractionDigits ? fractionDigits : pattern
        .minimumFractionDigits;
    size_t integerCount = primitiveWidth(integralDigits, pattern);
    const fallbackZero = integerCount == 0 && fractionCount == 0;
    // A negative start pads with zeros. A positive start skips truncated leading digits.
    // For the digitless fallback, start after the stored digits to emit a zero.
    const first = fallbackZero ? cast(int) digits.length : cast(int) integralDigits - cast(int) integerCount;
    integerCount += fallbackZero;
    const groups = integerCount && pattern.groupingSize ? (integerCount - 1) / pattern.groupingSize : 0;
    const decimalPoint = fractionCount != 0 || pattern.decimalSeparatorAlwaysShown;
    const required = cast(ulong) affixes.prefix.length + integerCount + groups + decimalPoint
        + fractionCount + affixes.suffix.length;
    if (required > output.length)
        return required > size_t.max ? size_t.max : cast(size_t) required;

    const prefixEnd = affixes.prefix.length;
    output[0 .. prefixEnd] = affixes.prefix;
    size_t at = prefixEnd + integerCount + groups;
    writeInteger(digits, first, integerCount, pattern.groupingSize, symbols, output[prefixEnd .. at]);
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

private size_t primitiveWidth(size_t integralDigits, ref scope const DecimalFixedPattern pattern) pure nothrow @nogc
{
    enum primitiveLimit = 309;
    const maximum = pattern.maximumIntegerDigits < primitiveLimit ? pattern.maximumIntegerDigits : primitiveLimit;
    const width = integralDigits > pattern.minimumIntegerDigits ? integralDigits : pattern.minimumIntegerDigits;
    return width < maximum ? width : maximum;
}

private void writeInteger(scope const(char)[] digits, int firstDigit, size_t integerCount,
        uint groupingSize, ref scope const DecimalSymbolData symbols, scope char[] output) pure nothrow @nogc
{
    size_t at;
    foreach (i; 0 .. integerCount)
    {
        if (i != 0 && groupingSize && (integerCount - i) % groupingSize == 0)
            output[at++] = cast(char) symbols.groupingSeparator;
        const index = firstDigit + cast(int) i;
        if (index >= 0 && index < digits.length)
            output[at++] = digits[cast(size_t) index];
        else
            output[at++] = cast(char) symbols.zeroDigit;
    }
}
