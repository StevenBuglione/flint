/// Bounded tokenization and Unicode decoding for UTF-8 JSON input.
module flint.serde.internal.json_scan;

import flint.arena : Error, Status;
import flint.serde.internal.types : DecodeOptions;

@safe:

/// A validated string's contents and decoded UTF-8 length.
struct TextToken
{
    /// Beginning of the contents after the opening quote.
    size_t start;
    /// Offset of the closing quote.
    size_t end;
    /// Decoded UTF-8 bytes.
    size_t length;
    /// Lookup hash of the decoded Unicode scalar sequence.
    uint hash = nameHashSeed;
}

/// A validated JSON number's byte span.
struct NumberToken
{
    /// Offset of the first byte.
    size_t start;
    /// Offset after the last byte.
    size_t end;
    /// Whether the token uses a fraction or an exponent.
    bool fractional;
}

/// Seed for the decoded member-name hash.
enum uint nameHashSeed = 2_166_136_261;

/// Mix a Unicode scalar into a member-name hash.
uint advanceNameHash(uint hash, uint scalar) pure nothrow @nogc
{
    return (hash ^ scalar) * 16_777_619;
}

/// Recognize a decimal digit without target locale rules.
bool digit(ubyte byteValue) nothrow @nogc
{
    return byteValue >= '0' && byteValue <= '9';
}

/// Decode the next Unicode scalar from raw UTF-8.
bool utf8Scalar(scope const(ubyte)[] bytes, ref size_t offset, out uint scalar) nothrow @nogc
{
    if (offset == bytes.length)
        return false;

    immutable first = bytes[offset++];
    if (first < 0x80)
    {
        scalar = first;
        return true;
    }

    const leading = classifyLeading(first);
    const following = leading.following;
    if (following == 0)
        return false;
    scalar = leading.payload;
    if (following > bytes.length - offset)
        return false;

    foreach (index; 0 .. following)
    {
        immutable continuation = bytes[offset++];
        if ((continuation & 0xc0) != 0x80)
            return false;
        scalar = (scalar << 6) | (continuation & 0x3f);
    }
    return scalar >= leading.minimum && scalar <= 0x10_ffff && (scalar < 0xd800 || scalar > 0xdfff);
}

private struct Leading
{
    uint following;
    uint minimum;
    uint payload;
}

private Leading classifyLeading(ubyte first) nothrow @nogc
{
    if (first >= 0xc2 && first <= 0xdf)
        return Leading(1, 0x80, first & 0x1f);
    if (first >= 0xe0 && first <= 0xef)
        return Leading(2, 0x800, first & 0x0f);
    if (first >= 0xf0 && first <= 0xf4)
        return Leading(3, 0x1_0000, first & 0x07);
    return Leading.init;
}

/// Result of reading a Unicode scalar and advancing a borrowed cursor.
struct Codepoint
{
    /// Decoded scalar when valid.
    uint scalar;
    /// Whether decoding succeeded.
    bool valid;
}

/// Decode a Unicode scalar without an out parameter at the call site.
Codepoint readUtf8(scope const(ubyte)[] bytes, ref size_t offset) nothrow @nogc
{
    Codepoint point;
    point.valid = utf8Scalar(bytes, offset, point.scalar);
    return point;
}

private size_t utf8Length(uint scalar) nothrow @nogc
{
    if (scalar < 0x80)
        return 1;
    if (scalar < 0x800)
        return 2;
    return scalar < 0x1_0000 ? 3 : 4;
}

/// Write a Unicode scalar as one to four UTF-8 bytes.
size_t writeScalar(uint scalar, scope ref ubyte[4] bytes) nothrow @nogc
{
    immutable length = utf8Length(scalar);
    if (length == 1)
    {
        bytes[0] = cast(ubyte) scalar;
        return 1;
    }
    foreach_reverse (index; 1 .. length)
    {
        bytes[index] = cast(ubyte)(0x80 | (scalar & 0x3f));
        scalar >>= 6;
    }
    immutable ubyte[4] leading = [0, 0xc0, 0xe0, 0xf0];
    bytes[0] = cast(ubyte)(leading[length - 1] | scalar);
    return length;
}

private bool hexWord(scope const(ubyte)[] bytes, ref size_t offset, out uint scalar) nothrow @nogc
{
    if (bytes.length - offset < 4)
        return false;
    uint value;
    foreach (index; 0 .. 4)
    {
        immutable byteValue = bytes[offset++];
        value <<= 4;
        if (byteValue >= '0' && byteValue <= '9')
            value |= byteValue - '0';
        else if (byteValue >= 'A' && byteValue <= 'F')
            value |= byteValue - 'A' + 10;
        else if (byteValue >= 'a' && byteValue <= 'f')
            value |= byteValue - 'a' + 10;
        else
            return false;
    }
    scalar = value;
    return true;
}

private Codepoint stringScalar(scope const(ubyte)[] bytes, ref size_t offset) nothrow @nogc
{
    if (offset == bytes.length)
        return Codepoint.init;
    if (bytes[offset] != '\\')
    {
        auto point = readUtf8(bytes, offset);
        if (point.scalar < 0x20)
            point.valid = false;
        return point;
    }
    ++offset;
    if (offset == bytes.length)
        return Codepoint.init;

    const escape = bytes[offset++];
    if (escape == 'u')
        return unicodeScalar(bytes, offset);

    enum spellings = "\"\\/bfnrt";
    enum meanings = "\"\\/\b\f\n\r\t";
    foreach (index, spelling; spellings)
    {
        if (escape == spelling)
            return Codepoint(meanings[index], true);
    }
    return Codepoint.init;
}

private Codepoint unicodeScalar(scope const(ubyte)[] bytes, ref size_t offset) nothrow @nogc
{
    Codepoint point;
    if (!hexWord(bytes, offset, point.scalar))
        return Codepoint.init;
    if (point.scalar < 0xd800 || point.scalar > 0xdfff)
        return Codepoint(point.scalar, true);
    if (point.scalar >= 0xdc00 || bytes.length - offset < 2 || bytes[offset] != '\\' || bytes[offset + 1] != 'u')
        return Codepoint.init;
    offset += 2;
    Codepoint low;
    if (!hexWord(bytes, offset, low.scalar) || low.scalar < 0xdc00 || low.scalar > 0xdfff)
        return Codepoint.init;
    return Codepoint(0x1_0000 + ((point.scalar - 0xd800) << 10) + (low.scalar - 0xdc00), true);
}

/// Compare a validated token to a decoded UTF-8 name.
bool textEquals(scope const(ubyte)[] bytes, TextToken token, scope const(ubyte)[] expected) nothrow @nogc
{
    if (token.length != expected.length)
        return false;
    size_t offset = token.start;
    size_t index;
    while (offset < token.end)
    {
        const point = stringScalar(bytes, offset);
        if (!point.valid)
            return false;
        ubyte[4] encoded;
        immutable count = writeScalar(point.scalar, encoded);
        foreach (byteValue; encoded[0 .. count])
        {
            if (expected[index++] != byteValue)
                return false;
        }
    }
    return true;
}

/// Compare two validated keys by decoded Unicode scalar sequence.
bool textTokensEqual(scope const(ubyte)[] bytes, TextToken left, TextToken right) nothrow @nogc
{
    if (left.length != right.length)
        return false;
    while (left.start < left.end && right.start < right.end)
    {
        const first = stringScalar(bytes, left.start);
        const second = stringScalar(bytes, right.start);
        if (!first.valid || !second.valid || first.scalar != second.scalar)
            return false;
    }
    return left.start == left.end && right.start == right.end;
}

/// Materialize a validated JSON string in its exact-sized destination.
bool copyText(scope const(ubyte)[] input, TextToken token, scope ubyte[] output) nothrow @nogc
{
    if (output.length != token.length)
        return false;

    size_t offset = token.start;
    size_t written;
    while (offset < token.end)
    {
        const point = stringScalar(input, offset);
        if (!point.valid)
            return false;
        ubyte[4] encoded;
        immutable length = writeScalar(point.scalar, encoded);
        foreach (index; 0 .. length)
            output[written++] = encoded[index];
    }
    return written == output.length;
}

/// A borrower over one JSON document with no allocator or runtime dependency.
struct Scanner
{
    /// Source document.
    const(ubyte)[] bytes;
    /// Current byte offset.
    size_t offset;
    /// Bounds and duplicate-key policy.
    DecodeOptions options;

    /// Keep the source borrowed for the scanner's lifetime.
    this(return scope const(ubyte)[] bytes, DecodeOptions options) nothrow @nogc
    {
        this.bytes = bytes;
        this.options = options;
    }

    /// Skip the four whitespace bytes recognized by JSON.
    void whitespace() scope nothrow @nogc
    {
        while (offset < bytes.length)
        {
            switch (bytes[offset])
            {
            case ' ', '\t', '\n', '\r':
                ++offset;
                break;
            default:
                return;
            }
        }
    }

    /// Consume one expected byte without moving on a mismatch.
    bool take(ubyte expected) scope nothrow @nogc
    {
        if (offset == bytes.length || bytes[offset] != expected)
            return false;
        ++offset;
        return true;
    }

    /// Return the next byte, using zero as an end sentinel.
    ubyte peek() const scope nothrow @nogc
    {
        return offset == bytes.length ? 0 : bytes[offset];
    }

    /// Consume the requested fixed token.
    bool literal(scope const(ubyte)[] expected) scope nothrow @nogc
    {
        if (expected.length > bytes.length - offset)
            return false;
        foreach (index, byteValue; expected)
        {
            if (bytes[offset + index] != byteValue)
                return false;
        }
        offset += expected.length;
        return true;
    }

    /// Read and validate a quoted string without materializing it.
    Error text(out TextToken token) scope nothrow @nogc
    {
        if (!take('"'))
            return Error(Status.invalidArgument, "expected a JSON string", offset);

        token.start = offset;
        while (offset < bytes.length)
        {
            immutable position = offset;
            if (take('"'))
            {
                token.end = position;
                return Error.init;
            }
            const point = stringScalar(bytes, offset);
            if (!point.valid)
                return Error(Status.invalidArgument, "invalid JSON string", position);
            token.length += utf8Length(point.scalar);
            token.hash = advanceNameHash(token.hash, point.scalar);
        }
        return Error(Status.invalidArgument, "unterminated JSON string", offset);
    }

    /// Read one RFC 8259 number without converting its value.
    Error number(out NumberToken token) scope nothrow @nogc
    {
        token.start = offset;
        if (peek() == '-')
            ++offset;
        if (!take('0'))
        {
            if (!digit(peek()))
                return Error(Status.invalidArgument, "expected a JSON number", token.start);
            digits();
        }

        if (take('.'))
        {
            token.fractional = true;
            if (!digit(peek()))
                return Error(Status.invalidArgument, "expected fraction digits", offset);
            digits();
        }
        if (take('e') || take('E'))
        {
            token.fractional = true;
            if (peek() == '-' || peek() == '+')
                ++offset;
            if (!digit(peek()))
                return Error(Status.invalidArgument, "expected exponent digits", offset);
            digits();
        }
        token.end = offset;
        return Error.init;
    }

    private void digits() scope nothrow @nogc
    {
        while (digit(peek()))
            ++offset;
    }
}

private struct Container
{
    ubyte close;
    size_t firstMember;
    uint members;
    ulong possibleDuplicate;
}

/// Validate and consume an unbound JSON value with an explicit container stack.
Error skipValue(ref scope Scanner scanner, uint parentDepth, bool checkDuplicates = true) nothrow @nogc
{
    Container[64] stack;
    size_t depth;
    bool needValue = true;
    for (;;)
    {
        scanner.whitespace();
        if (needValue)
        {
            immutable next = scanner.peek();
            if (next == '{' || next == '[')
            {
                if (depth == stack.length || parentDepth + depth >= scanner.options.maxDepth)
                    return Error(Status.resourceExhausted, "JSON depth limit exceeded", scanner.offset);
                ++scanner.offset;
                immutable close = cast(ubyte)(next == '{' ? '}' : ']');
                stack[depth++] = Container(close, scanner.offset);
            }
            else
            {
                auto failure = skipScalar(scanner);
                if (failure.code != Status.ok)
                    return failure;
                if (depth == 0)
                    return Error.init;
            }
            needValue = false;
        }
        else
        {
            if (depth == 0)
                return Error.init;
            scope container = &stack[depth - 1];
            if (scanner.take(container.close))
            {
                --depth;
                continue;
            }
            const failure = skipMember(scanner, *container, parentDepth + cast(uint) depth, checkDuplicates);
            if (failure.code != Status.ok)
                return failure;
            needValue = true;
        }
    }
}

private Error skipMember(ref scope Scanner scanner, ref Container container, uint depth, bool checkKeys) nothrow @nogc
{
    if (container.members != 0 && !scanner.take(','))
        return Error(Status.invalidArgument, "expected a JSON member separator", scanner.offset);
    if (container.members == scanner.options.maxMembers)
        return Error(Status.resourceExhausted, "JSON member limit exceeded", scanner.offset);

    scanner.whitespace();
    if (container.close == '}')
    {
        TextToken key;
        immutable keyOffset = scanner.offset;
        auto failure = scanner.text(key);
        if (failure.code != Status.ok)
            return failure;
        immutable fingerprint = 1UL << (key.hash & 63);
        if (checkKeys && scanner.options.rejectDuplicateKeys && (container.possibleDuplicate & fingerprint) != 0
                && earlierKey(scanner, container.firstMember, keyOffset, key, depth))
            return Error(Status.invalidArgument, "duplicate JSON member", keyOffset);
        container.possibleDuplicate |= fingerprint;
        scanner.whitespace();
        if (!scanner.take(':'))
            return Error(Status.invalidArgument, "expected a JSON member colon", scanner.offset);
    }
    ++container.members;
    return Error.init;
}

/// Test a key against earlier keys in the same validated object without storing their bytes.
bool earlierKey(ref scope Scanner scanner, size_t start, size_t end, TextToken key, uint depth) nothrow @nogc
{
    scope previous = Scanner(scanner.bytes, scanner.options);
    previous.offset = start;
    while (previous.offset < end)
    {
        previous.whitespace();
        if (previous.offset >= end)
            break;
        TextToken earlier;
        if (previous.text(earlier).code != Status.ok)
            return false;
        if (earlier.hash == key.hash && textTokensEqual(scanner.bytes, earlier, key))
            return true;
        previous.whitespace();
        if (!previous.take(':') || skipValue(previous, depth, false).code != Status.ok)
            return false;
        previous.whitespace();
        if (!previous.take(','))
            break;
    }
    return false;
}

private Error skipScalar(ref scope Scanner scanner) nothrow @nogc
{
    switch (scanner.peek())
    {
    case '"':
        TextToken text;
        return scanner.text(text);
    case 't':
        if (scanner.literal(cast(const(ubyte)[]) "true"))
            return Error.init;
        break;
    case 'f':
        if (scanner.literal(cast(const(ubyte)[]) "false"))
            return Error.init;
        break;
    case 'n':
        if (scanner.literal(cast(const(ubyte)[]) "null"))
            return Error.init;
        break;
    default:
        NumberToken number;
        return scanner.number(number);
    }
    return Error(Status.invalidArgument, "invalid JSON scalar", scanner.offset);
}
