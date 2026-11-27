// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Lexical ranges in a nonlocalized DecimalFormat pattern.
module flint.java.text.internal.decimalpattern;

import flint.java.text.internal.decimalfixed : affixFieldWords, DecimalAffixes, DecimalField,
    DecimalFixedPattern, minusSignField;

@safe:

package(flint.java.text):

/// UTF-8 byte boundaries within the original pattern.
struct DecimalSubpatternBounds
{
    size_t start;
    size_t digitsStart;
    size_t digitsEnd;
    size_t end;
}

struct DecimalPatternBounds
{
    DecimalSubpatternBounds positive;
    DecimalSubpatternBounds negative;
    bool hasNegative;
}

/// Partition the raw pattern. Digit ordering, exponents and affix expansion are validated separately.
bool scanDecimalPattern(scope string pattern, out DecimalPatternBounds bounds) pure nothrow @nogc
{
    size_t position;
    DecimalPatternBounds split;
    if (!scanSubpattern(pattern, position, true, split.positive))
        return false;
    if (position < pattern.length)
    {
        split.hasNegative = true;
        ++position;
        if (!scanSubpattern(pattern, position, false, split.negative) || position < pattern.length)
            return false;
    }
    bounds = split;
    return true;
}

struct DecimalDigitSettings
{
    uint minimumIntegerDigits;
    uint minimumFractionDigits;
    uint maximumFractionDigits;
    uint groupingSize;
    bool decimalSeparatorAlwaysShown;
    uint maximumIntegerDigits = int.max;
    // Zero for fixed-point patterns; Java keeps the exponent width in a signed byte.
    ubyte minimumExponentDigits;
}

enum DecimalDigitStatus
{
    accepted,
    malformed,
}

/// Resolve the positive digit span of a nonlocalized fixed-point or exponent pattern.
DecimalDigitStatus readDecimalDigits(scope string pattern, out DecimalDigitSettings settings) pure nothrow @nogc
{
    if (pattern.length > int.max)
        return DecimalDigitStatus.malformed;
    DigitShape shape;
    const status = scanDigitShape(pattern, shape);
    if (status != DecimalDigitStatus.accepted)
        return status;

    const integerDigits = shape.point < 0 ? shape.count : shape.point;
    if (shape.firstRequired < 0)
        defaultRequiredDigit(shape);
    if (integerDigits < shape.firstRequired || integerDigits > shape.requiredEnd)
        return DecimalDigitStatus.malformed;

    const width = shape.lastGroup < 0 ? 0 : integerDigits - shape.lastGroup;
    if (shape.lastGroup >= 0 && width == 0)
        return DecimalDigitStatus.malformed;
    // Java stores the grouping interval in a signed byte and disables grouping when it overflows.
    auto resolved = DecimalDigitSettings(cast(uint)(integerDigits - shape.firstRequired),
            cast(uint)(shape.requiredEnd - integerDigits), cast(uint)(shape.count - integerDigits),
            width <= byte.max ? cast(uint) width : 0, shape.point == 0 || shape.point == shape.count);
    if (shape.exponent >= 0 && !readExponent(pattern[shape.exponent + 1 .. $], shape.count, integerDigits, resolved))
        return DecimalDigitStatus.malformed;
    settings = resolved;
    return DecimalDigitStatus.accepted;
}

enum DecimalCompileStatus
{
    accepted,
    malformed,
    currency,
    splitDigits,
}

/// Compile a nonlocalized fixed-point or exponent pattern with the explicit Latin symbol profiles.
DecimalCompileStatus compileFixedDecimalPattern(scope string text, out DecimalFixedPattern result) pure nothrow
{
    DecimalPatternBounds bounds;
    if (!scanDecimalPattern(text, bounds))
        return DecimalCompileStatus.malformed;
    DecimalDigitSettings digits;
    auto status = readPositiveDigits(text, bounds, digits);
    if (status != DecimalCompileStatus.accepted)
        return status;
    AffixPair positive;
    status = readAffixes(text, bounds.positive, positive);
    if (status != DecimalCompileStatus.accepted)
        return status;
    AffixPair negative;
    const explicitNegative = bounds.hasNegative && bounds.negative.start != bounds.negative.end;
    if (explicitNegative)
    {
        status = readAffixes(text, bounds.negative, negative);
        if (status != DecimalCompileStatus.accepted)
            return status;
    }
    result.minimumIntegerDigits = digits.minimumIntegerDigits;
    result.maximumIntegerDigits = digits.maximumIntegerDigits;
    result.minimumExponentDigits = digits.minimumExponentDigits;
    result.minimumFractionDigits = digits.minimumFractionDigits;
    result.maximumFractionDigits = text.length ? digits.maximumFractionDigits : 3;
    result.groupingSize = text.length ? digits.groupingSize : 3;
    result.decimalSeparatorAlwaysShown = digits.decimalSeparatorAlwaysShown;
    result.scale = positive.scale;
    result.positive = DecimalAffixes(positive.prefix.text, positive.suffix.text,
            positive.prefix.fields, positive.suffix.fields);
    if (explicitNegative && !sameAffixes(positive, negative))
        result.negative = DecimalAffixes(negative.prefix.text, negative.suffix.text,
                negative.prefix.fields, negative.suffix.fields);
    else
        result.negative = DecimalAffixes("-" ~ positive.prefix.text, positive.suffix.text,
                signedFields(positive.prefix.fields), positive.suffix.fields);
    return DecimalCompileStatus.accepted;
}

private:

DecimalCompileStatus readPositiveDigits(scope string text, ref const DecimalPatternBounds bounds,
        out DecimalDigitSettings digits) pure nothrow @nogc
{
    if (bounds.hasNegative && bounds.positive.digitsStart == bounds.positive.digitsEnd)
        return DecimalCompileStatus.malformed;
    // Java resumes the positive digit phase at an unquoted suffix digit, so the span is incomplete.
    if (reentersDigits(text[bounds.positive.digitsEnd .. bounds.positive.end]))
        return DecimalCompileStatus.splitDigits;
    const span = text[bounds.positive.digitsStart .. bounds.positive.digitsEnd];
    return readDecimalDigits(span, digits) == DecimalDigitStatus.accepted
        ? DecimalCompileStatus.accepted : DecimalCompileStatus.malformed;
}

/// Count the exponent's zeros after at least one digit token, wrapping like Java's byte counter.
pure nothrow @nogc bool readExponent(scope string zeros, int digitTokens, int integerDigits,
        ref DecimalDigitSettings settings)
{
    byte width;
    foreach (token; zeros)
    {
        if (token != '0')
            return false;
        ++width;
    }
    if (digitTokens < 1 || width < 1)
        return false;
    // An exponent pattern's integer span is also its maximum, which sets the engineering repeat.
    settings.maximumIntegerDigits = cast(uint) integerDigits;
    settings.minimumExponentDigits = cast(ubyte) width;
    return true;
}

pure nothrow @nogc bool scanSubpattern(scope string pattern, ref size_t position, bool positive,
        out DecimalSubpatternBounds bounds)
{
    const start = position;
    if (!scanAffix(pattern, position, true))
        return false;
    const digitsStart = position;
    while (position < pattern.length && (numericToken(pattern[position]) || pattern[position] == 'E'))
    {
        if (pattern[position++] != 'E' || !positive)
            continue;
        // Java leaves the positive digit phase after the exponent's zeros; the negative one skips on.
        while (position < pattern.length && pattern[position] == '0')
            ++position;
        break;
    }
    const digitsEnd = position;
    if (!scanAffix(pattern, position, false))
        return false;
    bounds = DecimalSubpatternBounds(start, digitsStart, digitsEnd, position);
    return true;
}

bool numericToken(char token) pure nothrow @nogc
{
    return token == '#' || token == '0' || token == ',' || token == '.';
}

bool scanAffix(scope string pattern, ref size_t position, bool prefix) pure nothrow @nogc
{
    while (position < pattern.length)
    {
        const token = pattern[position];
        if (token == ';' || (prefix && numericToken(token)))
            break;
        if (token == '\'')
        {
            if (!scanQuoted(pattern, position))
                return false;
        }
        else
            ++position;
    }
    return true;
}

bool reentersDigits(scope string suffix) pure nothrow @nogc
{
    for (size_t position; position < suffix.length;)
    {
        if (suffix[position] == '\'')
        {
            if (!scanQuoted(suffix, position))
                return false;
        }
        else if (numericToken(suffix[position++]))
            return true;
    }
    return false;
}

bool scanQuoted(scope string pattern, ref size_t position) pure nothrow @nogc
{
    ++position;
    while (position < pattern.length)
    {
        if (pattern[position++] != '\'')
            continue;
        if (position == pattern.length || pattern[position] != '\'')
            return true;
        ++position;
    }
    return false;
}

struct DigitShape
{
    int count;
    int firstRequired = -1;
    int requiredEnd;
    int point = -1;
    int lastGroup = -1;
    int exponent = -1;
}

DecimalDigitStatus scanDigitShape(scope string pattern, out DigitShape shape) pure nothrow @nogc
{
    foreach (index, token; pattern)
    {
        switch (token)
        {
        case '#':
            ++shape.count;
            break;
        case '0':
            if (shape.firstRequired < 0)
                shape.firstRequired = shape.count;
            else if (shape.requiredEnd != shape.count)
                return DecimalDigitStatus.malformed;
            shape.requiredEnd = ++shape.count;
            break;
        case '.':
            if (shape.point >= 0)
                return DecimalDigitStatus.malformed;
            shape.point = shape.count;
            break;
        case ',':
            if (shape.point >= 0)
                return DecimalDigitStatus.malformed;
            shape.lastGroup = shape.count;
            break;
        case 'E':
            shape.exponent = cast(int) index;
            return DecimalDigitStatus.accepted;
        default:
            return DecimalDigitStatus.malformed;
        }
    }
    return DecimalDigitStatus.accepted;
}

void defaultRequiredDigit(ref DigitShape shape) pure nothrow @nogc
{
    // With zero mandatory tokens, a decimal pattern keeps one digit next to the point.
    if (shape.point >= 0 && shape.count != 0)
    {
        shape.firstRequired = shape.point == 0 ? 0 : shape.point - 1;
        shape.requiredEnd = shape.firstRequired + 1;
    }
    else
    {
        shape.firstRequired = shape.count;
        shape.requiredEnd = shape.count;
    }
}

struct DecodedAffix
{
    string text;
    // Rendered (DecimalField, begin, end) triples of symbolic pattern tokens, including unquoted minus signs.
    size_t[] fields;
}

// The implicit negative prefix puts the symbolic minus sign ahead of the positive prefix tokens.
size_t[] signedFields(scope const(size_t)[] fields) pure nothrow
{
    size_t[] result;
    foreach (word; minusSignField)
        appendWord(result, word);
    foreach (i, word; fields)
        appendWord(result, i % affixFieldWords == 0 ? word : word + "-".length);
    return result;
}

// One append site keeps the template count at the single size_t[] instance (B-93).
void appendWord(ref size_t[] words, size_t word) pure nothrow
{
    words ~= word;
}

struct AffixPair
{
    DecodedAffix prefix;
    DecodedAffix suffix;
    ubyte scale;
}

bool sameAffixes(ref scope const AffixPair positive, ref scope const AffixPair negative) pure nothrow @nogc
{
    return positive.prefix.text == negative.prefix.text
        && positive.suffix.text == negative.suffix.text
        && positive.prefix.fields == negative.prefix.fields && positive.suffix.fields == negative.suffix.fields;
}

DecimalCompileStatus readAffixes(scope string text, DecimalSubpatternBounds bounds, out AffixPair result) pure nothrow
{
    const prefixStatus = decodeAffix(text[bounds.start .. bounds.digitsStart], result.scale, result.prefix);
    if (prefixStatus != DecimalCompileStatus.accepted)
        return prefixStatus;
    return decodeAffix(text[bounds.digitsEnd .. bounds.end], result.scale, result.suffix);
}

enum AffixOperator
{
    literal,
    minus,
    percent,
    perMille,
    currency,
    digits,
}

AffixOperator affixOperator(scope string text) pure nothrow @nogc
{
    switch (text[0])
    {
    case '-':
        return AffixOperator.minus;
    case '%':
        return AffixOperator.percent;
    case '#', '0', ',', '.':
        return AffixOperator.digits;
    default:
        if (text.length >= "‰".length && text[0 .. "‰".length] == "‰")
            return AffixOperator.perMille;
        if (text.length >= "¤".length && text[0 .. "¤".length] == "¤")
            return AffixOperator.currency;
        return AffixOperator.literal;
    }
}

DecimalField affixField(AffixOperator operation) pure nothrow @nogc
{
    switch (operation)
    {
    case AffixOperator.percent:
        return DecimalField.percent;
    case AffixOperator.perMille:
        return DecimalField.perMille;
    default:
        return DecimalField.sign;
    }
}

DecimalCompileStatus decodeAffix(scope string raw, ref ubyte scale, out DecodedAffix result) pure nothrow
{
    bool quoted;
    for (size_t position; position < raw.length;)
    {
        const token = raw[position];
        if (token == '\'')
        {
            ++position;
            if (position < raw.length && raw[position] == '\'')
            {
                result.text ~= '\'';
                ++position;
            }
            else
                quoted = !quoted;
            continue;
        }
        const operation = quoted ? AffixOperator.literal : affixOperator(raw[position .. $]);
        if (operation == AffixOperator.digits)
            return DecimalCompileStatus.splitDigits;
        if (operation == AffixOperator.currency)
            return DecimalCompileStatus.currency;
        const width = operation == AffixOperator.perMille ? "‰".length : 1;
        if (operation == AffixOperator.percent || operation == AffixOperator.perMille)
        {
            if (scale != 0)
                return DecimalCompileStatus.malformed;
            scale = operation == AffixOperator.percent ? 2 : 3;
        }
        if (operation != AffixOperator.literal)
        {
            appendWord(result.fields, affixField(operation));
            appendWord(result.fields, result.text.length);
            appendWord(result.fields, result.text.length + width);
        }
        result.text ~= raw[position .. position + width];
        position += width;
    }
    return DecimalCompileStatus.accepted;
}
