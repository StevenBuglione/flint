// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Fixed-point rendering for resolved DecimalFormat patterns.
module flint.java.text.internal.decimalfixed;

import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, encodeSymbol;

@safe:

package(flint.java.text):

struct DecimalAffixes
{
    string prefix;
    string suffix;
    // Each symbolic token is a (DecimalField, begin, end) triple of UTF-8 offsets within its affix text.
    // Flat words reuse the compiler's existing size_t[] append and comparison instances (B-93).
    const(size_t)[] prefixFields;
    const(size_t)[] suffixFields;
}

enum affixFieldWords = 3;

// Java's implicit negative prefix is the symbolic minus sign.
immutable size_t[affixFieldWords] minusSignField = [DecimalField.sign, 0, "-".length];

struct DecimalFixedPattern
{
    DecimalAffixes positive;
    DecimalAffixes negative = DecimalAffixes("-", null, minusSignField[]);
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

/// The NumberFormat.Field kinds the renderer reports from the number body and the symbolic affix tokens.
enum DecimalField : ubyte
{
    integer,
    fraction,
    groupingSeparator,
    decimalSeparator,
    exponentSymbol,
    exponentSign,
    exponent,
    sign,
    percent,
    perMille,
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

    // No affix field kind is also a body field, so recording the affixes after the body keeps Java's order.
    void recordAffixes(ref scope const DecimalAffixes affixes, size_t suffixStart) pure nothrow @nogc
    {
        recordAffix(affixes.prefixFields, 0);
        recordAffix(affixes.suffixFields, suffixStart);
    }

    private void recordAffix(scope const(size_t)[] affixFields, size_t start) pure nothrow @nogc
    {
        for (size_t i; i + affixFieldWords <= affixFields.length; i += affixFieldWords)
            record(cast(DecimalField) affixFields[i], start + affixFields[i + 1], start + affixFields[i + 2]);
    }
}

/// Writes with the given numeric symbols, which `bodySymbolsEncodable` must accept.
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

/// Primitive values use NumberFormat's 309/340 capped widths; `arbitraryWidths` selects DecimalFormat's own
/// widths, which BigInteger and BigDecimal formatting reads.
pure nothrow @nogc size_t renderFixedDigits(scope const(char)[] digits, int decimalAt, bool negative,
        ref scope const DecimalFixedPattern pattern, ref scope const DecimalSymbolData symbols,
        scope char[] output, scope DecimalFieldSpans* fields = null, bool arbitraryWidths = false)
{
    const affixes = negative ? pattern.negative : pattern.positive;
    const integralDigits = decimalAt > 0 ? cast(size_t) decimalAt : 0;
    const visibleFraction = cast(int) digits.length - decimalAt;
    const fractionDigits = visibleFraction > 0 ? cast(size_t) visibleFraction : 0;
    const minimumFraction = arbitraryWidths ? pattern.minimumFractionDigits
        : primitiveFractionWidth(pattern.minimumFractionDigits);
    const fractionCount = fractionDigits > minimumFraction ? fractionDigits : minimumFraction;
    size_t integerCount = integerWidth(integralDigits, pattern, arbitraryWidths);
    const fallbackZero = integerCount == 0 && fractionCount == 0;
    // A negative start pads with zeros. A positive start skips truncated leading digits.
    // For the digitless fallback, start after the stored digits to emit a zero.
    const first = fallbackZero ? cast(int) digits.length : cast(int) integralDigits - cast(int) integerCount;
    integerCount += fallbackZero;
    const groups = integerCount && pattern.groupingSize ? (integerCount - 1) / pattern.groupingSize : 0;
    const decimalPoint = fractionCount != 0 || pattern.decimalSeparatorAlwaysShown;
    const localized = BodySymbols(symbols);
    const integerBytes = localized.runWidth(digits, first, integerCount) + cast(ulong) groups * localized.groupingWidth;
    const fractionBytes = localized.runWidth(digits, decimalAt, fractionCount);
    const decimalBytes = decimalPoint ? localized.decimalWidth : 0;
    const required = cast(ulong) affixes.prefix.length + integerBytes + decimalBytes + fractionBytes
        + affixes.suffix.length;
    if (required > output.length)
        return required > size_t.max ? size_t.max : cast(size_t) required;

    const prefixEnd = affixes.prefix.length;
    output[0 .. prefixEnd] = affixes.prefix;
    size_t at = prefixEnd + cast(size_t) integerBytes;
    const separator = writeInteger(digits, first, integerCount, pattern.groupingSize, localized,
            output[prefixEnd .. at]);
    const integerEnd = at;
    if (decimalPoint)
        at = localized.putDecimal(output, at);
    const fractionStart = at;
    at += cast(size_t) fractionBytes;
    writeFraction(digits, decimalAt, localized, output[fractionStart .. at]);
    output[at .. cast(size_t) required] = affixes.suffix;
    if (fields !is null)
    {
        // Java reports the integer digits with their separators, then the decimal separator, then the fraction.
        if (groups != 0)
            fields.record(DecimalField.groupingSeparator, prefixEnd + separator,
                    prefixEnd + separator + localized.groupingWidth);
        fields.record(DecimalField.integer, prefixEnd, integerEnd);
        if (decimalPoint)
            fields.record(DecimalField.decimalSeparator, integerEnd, fractionStart);
        fields.record(DecimalField.fraction, fractionStart, at);
        fields.recordAffixes(affixes, at);
    }
    return cast(size_t) required;
}

/// The UTF-8 forms of the symbols written in a number body.
/// Java writes each digit as the 16-bit sum of the zero digit and the digit's value.
struct BodySymbols
{
    char[3][10] digits;
    ubyte[10] digitWidths;
    // Zero when the ten digits straddle a UTF-8 width boundary, as zero digits just below U+0800 do.
    ubyte uniformWidth;
    char[3] grouping;
    ubyte groupingWidth;
    char[3] decimal;
    ubyte decimalWidth;
    char[3] minus;
    ubyte minusWidth;

    this(ref scope const DecimalSymbolData symbols) pure nothrow @nogc
    {
        foreach (digit; 0 .. 10)
            digitWidths[digit] = cast(ubyte) encodeSymbol(cast(wchar)(symbols.zeroDigit + digit), digits[digit]);
        uniformWidth = digitWidths[0] == digitWidths[9] ? digitWidths[0] : 0;
        groupingWidth = cast(ubyte) encodeSymbol(symbols.groupingSeparator, grouping);
        decimalWidth = cast(ubyte) encodeSymbol(symbols.decimalSeparator, decimal);
        minusWidth = cast(ubyte) encodeSymbol(symbols.minusSign, minus);
    }

    /// The bytes of `count` digit positions from `first`; positions outside the stored digits are zeros.
    ulong runWidth(scope const(char)[] stored, long first, size_t count) const pure nothrow @nogc
    {
        if (uniformWidth != 0)
            return cast(ulong) count * uniformWidth;
        ulong width;
        foreach (i; 0 .. count)
        {
            const index = first + cast(long) i;
            width += digitWidths[index >= 0 && index < stored.length ? stored[cast(size_t) index] - '0' : 0];
        }
        return width;
    }

    /// Writes the localized form of an ASCII digit and returns the next offset.
    size_t putDigit(scope char[] output, size_t at, char digit) const pure nothrow @nogc
    {
        const value = digit - '0';
        const width = digitWidths[value];
        output[at .. at + width] = digits[value][0 .. width];
        return at + width;
    }

    size_t putGrouping(scope char[] output, size_t at) const pure nothrow @nogc
    {
        output[at .. at + groupingWidth] = grouping[0 .. groupingWidth];
        return at + groupingWidth;
    }

    size_t putDecimal(scope char[] output, size_t at) const pure nothrow @nogc
    {
        output[at .. at + decimalWidth] = decimal[0 .. decimalWidth];
        return at + decimalWidth;
    }

    size_t putMinus(scope char[] output, size_t at) const pure nothrow @nogc
    {
        output[at .. at + minusWidth] = minus[0 .. minusWidth];
        return at + minusWidth;
    }
}

private void writeFraction(scope const(char)[] digits, int point, ref scope const BodySymbols localized,
        scope char[] output) pure nothrow @nogc
{
    size_t at;
    for (long index = point; at < output.length; ++index)
        at = localized.putDigit(output, at, index >= 0 && index < digits.length ? digits[cast(size_t) index] : '0');
}

private pure nothrow @nogc size_t integerWidth(size_t integralDigits,
        ref scope const DecimalFixedPattern pattern, bool arbitrary)
{
    enum primitiveLimit = 309;
    const maximum = arbitrary || pattern.maximumIntegerDigits < primitiveLimit
        ? pattern.maximumIntegerDigits : primitiveLimit;
    const width = integralDigits > pattern.minimumIntegerDigits ? integralDigits : pattern.minimumIntegerDigits;
    return width < maximum ? width : maximum;
}

uint primitiveFractionWidth(uint width) pure nothrow @nogc
{
    enum limit = 340;
    return width < limit ? width : limit;
}

// Returns the offset of the first grouping separator.
private size_t writeInteger(scope const(char)[] digits, int firstDigit, size_t integerCount,
        uint groupingSize, ref scope const BodySymbols localized, scope char[] output) pure nothrow @nogc
{
    size_t at;
    size_t separator;
    foreach (i; 0 .. integerCount)
    {
        if (i != 0 && groupingSize && (integerCount - i) % groupingSize == 0)
        {
            if (separator == 0)
                separator = at;
            at = localized.putGrouping(output, at);
        }
        const index = firstDigit + cast(long) i;
        at = localized.putDigit(output, at, index >= 0 && index < digits.length ? digits[cast(size_t) index] : '0');
    }
    return separator;
}
