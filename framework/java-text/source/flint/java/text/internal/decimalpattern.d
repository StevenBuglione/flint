// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Lexical ranges in a nonlocalized DecimalFormat pattern.
module flint.java.text.internal.decimalpattern;

import flint.java.text.internal.decimalfixed : DecimalAffixes, DecimalFixedPattern;

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
    if (!scanSubpattern(pattern, position, split.positive))
        return false;
    if (position < pattern.length)
    {
        split.hasNegative = true;
        ++position;
        if (!scanSubpattern(pattern, position, split.negative) || position < pattern.length)
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
}

enum DecimalDigitStatus
{
    accepted,
    malformed,
    exponential,
}

/// Resolve the positive digit span of a nonlocalized fixed-point pattern.
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
    settings = DecimalDigitSettings(cast(uint)(integerDigits - shape.firstRequired),
            cast(uint)(shape.requiredEnd - integerDigits), cast(uint)(shape.count - integerDigits),
            width <= byte.max ? cast(uint) width : 0, shape.point == 0 || shape.point == shape.count);
    return DecimalDigitStatus.accepted;
}

enum DecimalCompileStatus
{
    accepted,
    malformed,
    exponential,
    currency,
    splitDigits,
}

/// Compile a nonlocalized fixed-point pattern with the explicit Latin symbol profiles.
DecimalCompileStatus compileFixedDecimalPattern(scope string text, out DecimalFixedPattern result) pure nothrow
{
    DecimalPatternBounds bounds;
    if (!scanDecimalPattern(text, bounds))
        return DecimalCompileStatus.malformed;
    if (bounds.hasNegative && bounds.positive.digitsStart == bounds.positive.digitsEnd)
        return DecimalCompileStatus.malformed;
    DecimalDigitSettings digits;
    const digitStatus = readDecimalDigits(text[bounds.positive.digitsStart .. bounds.positive.digitsEnd], digits);
    if (digitStatus != DecimalDigitStatus.accepted)
        return digitStatus == DecimalDigitStatus.exponential ? DecimalCompileStatus.exponential
            : DecimalCompileStatus.malformed;
    AffixPair positive;
    auto status = readAffixes(text, bounds.positive, positive);
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
    result.minimumFractionDigits = digits.minimumFractionDigits;
    result.maximumFractionDigits = text.length ? digits.maximumFractionDigits : 3;
    result.groupingSize = text.length ? digits.groupingSize : 3;
    result.decimalSeparatorAlwaysShown = digits.decimalSeparatorAlwaysShown;
    result.scale = positive.scale;
    result.positive = DecimalAffixes(positive.prefix.text, positive.suffix.text);
    if (explicitNegative && !sameAffixes(positive, negative))
        result.negative = DecimalAffixes(negative.prefix.text, negative.suffix.text);
    else
        result.negative = DecimalAffixes("-" ~ positive.prefix.text, positive.suffix.text);
    return DecimalCompileStatus.accepted;
}

private:

bool scanSubpattern(scope string pattern, ref size_t position, out DecimalSubpatternBounds bounds) pure nothrow @nogc
{
    const start = position;
    if (!scanAffix(pattern, position, true))
        return false;
    const digitsStart = position;
    while (position < pattern.length && (numericToken(pattern[position]) || pattern[position] == 'E'))
        ++position;
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
}

DecimalDigitStatus scanDigitShape(scope string pattern, out DigitShape shape) pure nothrow @nogc
{
    foreach (token; pattern)
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
            return DecimalDigitStatus.exponential;
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
    // Rendered offsets that came from symbolic pattern tokens, including unquoted minus signs.
    size_t[] operators;
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
        && positive.prefix.operators == negative.prefix.operators
        && positive.suffix.operators == negative.suffix.operators;
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
            result.operators ~= result.text.length;
        result.text ~= raw[position .. position + width];
        position += width;
    }
    return DecimalCompileStatus.accepted;
}
