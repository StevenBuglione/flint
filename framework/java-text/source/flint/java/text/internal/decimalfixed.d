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
    // Nonzero selects exponential notation; Java keeps the width in a positive signed byte.
    ubyte minimumExponentDigits;

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

    void setMinimumFractionDigits(int width) pure nothrow @nogc
    {
        minimumFractionDigits = width < 0 ? 0 : cast(uint) width;
        if (maximumFractionDigits < minimumFractionDigits)
            maximumFractionDigits = minimumFractionDigits;
    }

    void setMaximumFractionDigits(int width) pure nothrow @nogc
    {
        maximumFractionDigits = width < 0 ? 0 : cast(uint) width;
        if (minimumFractionDigits > maximumFractionDigits)
            minimumFractionDigits = maximumFractionDigits;
    }
}

/// The NumberFormat.Field kinds the renderer reports from the number body.
enum DecimalField : ubyte
{
    integer,
    fraction,
    groupingSeparator,
    decimalSeparator,
    exponentSymbol,
    exponentSign,
    exponent,
}

struct DecimalFieldSpan
{
    size_t begin;
    size_t end;
    bool recorded;
}

/// UTF-8 byte offsets into the rendered output, written only by a render that fits its buffer.
/// An unrecorded field corresponds to Java's untouched 0:0 FieldPosition.
struct DecimalFieldSpans
{
    DecimalFieldSpan[DecimalField.max + 1] spans;

    // FieldPosition.Delegate keeps the first nonempty span and lets a later call replace an empty one.
    void record(DecimalField field, size_t begin, size_t end) pure nothrow @nogc
    {
        if (spans[field].recorded && spans[field].begin != spans[field].end)
            return;
        spans[field] = DecimalFieldSpan(begin, end, true);
    }
}

/// Writes using the ASCII numeric symbols of the explicit ROOT and English profiles.
/// Returns the required byte count and leaves a short buffer untouched.
size_t renderDecimalLong(long value, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output) pure nothrow @nogc
in (pattern.minimumExponentDigits == 0)
{
    const negative = value < 0;
    ulong magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    char[20] digits;
    const start = writeUnsignedDigits(magnitude, digits);
    const decimalAt = value == 0 ? 0 : cast(int)(digits.length - start + pattern.scale);
    return renderFixedDigits(digits[start .. $], decimalAt, negative, pattern, symbols, output);
}

/// Formats an exact signed long product with the explicit Java multiplier and the pattern's affixes.
pure nothrow @nogc size_t renderDecimalLong(long value, int multiplier, ref scope const DecimalFixedPattern pattern,
        ref scope const DecimalSymbolData symbols, scope char[] output, scope DecimalFieldSpans* fields = null)
in (pattern.minimumExponentDigits == 0)
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
    return renderFixedDigits(digits[start .. $], count, negative, pattern, symbols, output, fields);
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

size_t writeWideUnsignedDigits(ulong lower, uint upper, ref scope char[29] digits) pure nothrow @nogc
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
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols,
        scope char[] output, scope DecimalFieldSpans* fields = null)
{
    const affixes = negative ? pattern.negative : pattern.positive;
    const integralDigits = decimalAt > 0 ? cast(size_t) decimalAt : 0;
    const visibleFraction = cast(int) digits.length - decimalAt;
    const fractionDigits = visibleFraction > 0 ? cast(size_t) visibleFraction : 0;
    const minimumFraction = primitiveFractionWidth(pattern.minimumFractionDigits);
    const fractionCount = fractionDigits > minimumFraction ? fractionDigits : minimumFraction;
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
    if (fields !is null)
        recordFixedFields(*fields, prefixEnd, integerCount, groups ? pattern.groupingSize : 0,
                at - decimalPoint, decimalPoint, fractionCount);
    return cast(size_t) required;
}

// Java reports the integer digits with their separators, then the decimal separator, then the fraction.
private pure nothrow @nogc void recordFixedFields(ref scope DecimalFieldSpans fields, size_t integerStart,
        size_t integerCount, uint groupingSize, size_t integerEnd, bool decimalPoint, size_t fractionCount)
{
    if (groupingSize != 0)
    {
        const separator = integerStart + (integerCount - 1) % groupingSize + 1;
        fields.record(DecimalField.groupingSeparator, separator, separator + 1);
    }
    fields.record(DecimalField.integer, integerStart, integerEnd);
    if (decimalPoint)
        fields.record(DecimalField.decimalSeparator, integerEnd, integerEnd + 1);
    const fractionStart = integerEnd + decimalPoint;
    fields.record(DecimalField.fraction, fractionStart, fractionStart + fractionCount);
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

uint primitiveFractionWidth(uint width) pure nothrow @nogc
{
    enum limit = 340;
    return width < limit ? width : limit;
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
