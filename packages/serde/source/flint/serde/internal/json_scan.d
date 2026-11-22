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

// The decoded byte of a two-character JSON escape, or -1 for \\u and invalid escapes.
pragma(inline, true) private int shortEscape(ubyte spelling) pure nothrow @nogc
{
    switch (spelling)
    {
    case '"', '\\', '/':
        return spelling;
    case 'b':
        return '\b';
    case 'f':
        return '\f';
    case 'n':
        return '\n';
    case 'r':
        return '\r';
    case 't':
        return '\t';
    default:
        return -1;
    }
}

// Bytes that a JSON string carries unchanged and that need no UTF-8 decoding.
private bool plainText(ubyte byteValue) pure nothrow @nogc
{
    return byteValue >= 0x20 && byteValue < 0x80 && byteValue != '"' && byteValue != '\\';
}

/// Materialize a validated JSON string in its exact-sized destination.
bool copyText(scope const(ubyte)[] input, TextToken token, scope ubyte[] output) nothrow @nogc
{
    if (output.length != token.length || token.end > input.length)
        return false;

    size_t offset = token.start;
    size_t written;
    while (offset < token.end)
    {
        immutable run = offset;
        while (offset < token.end && plainText(input[offset]))
            ++offset;
        if (offset != run && !copyBytes(output, written, input[run .. offset]))
            return false;
        if (offset == token.end)
            break;

        if (!copyScalar(input, token.end, offset, output, written))
            return false;
    }
    return written == output.length;
}

// Copy one escape or non-ASCII scalar of a validated string.
pragma(inline, true) private bool copyScalar(scope const(ubyte)[] input, size_t end, ref size_t offset,
        scope ubyte[] output, ref size_t written) nothrow @nogc
{
    immutable first = offset;
    immutable escaped = input[offset] == '\\';
    if (escaped && offset + 1 < end)
    {
        immutable meaning = shortEscape(input[offset + 1]);
        if (meaning >= 0)
        {
            if (written == output.length)
                return false;
            output[written++] = cast(ubyte) meaning;
            offset += 2;
            return true;
        }
    }
    const point = stringScalar(input, offset);
    if (!point.valid)
        return false;
    if (!escaped)
        return copyBytes(output, written, input[first .. offset]);
    ubyte[4] encoded;
    immutable length = writeScalar(point.scalar, encoded);
    return copyBytes(output, written, encoded[0 .. length]);
}

// Append within a checked destination.
private bool copyBytes(scope ubyte[] output, ref size_t written, scope const(ubyte)[] bytes) nothrow @nogc
{
    if (bytes.length > output.length - written)
        return false;
    copyInto(output[written .. written + bytes.length], bytes);
    written += bytes.length;
    return true;
}

/// Copy equal-length spans with an element loop; slice assignment would need a runtime hook absent in BetterC.
void copyInto(scope ubyte[] destination, scope const(ubyte)[] source) pure nothrow @nogc
{
    foreach (index; 0 .. source.length)
        destination[index] = source[index];
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
    /// Exact member index shared by the open objects, when the caller supplies one.
    KeyIndex* keys;

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

    /// Read and validate a quoted member name, including its lookup hash.
    Error text(out TextToken token) scope nothrow @nogc
    {
        return quoted!true(token);
    }

    /// Read and validate a quoted string value; its lookup hash is not computed.
    Error textValue(out TextToken token) scope nothrow @nogc
    {
        return quoted!false(token);
    }

    private Error quoted(bool hashed)(out TextToken token) scope nothrow @nogc
    {
        if (!take('"'))
            return Error(Status.invalidArgument, "expected a JSON string", offset);

        token.start = offset;
        size_t length;
        uint hash = nameHashSeed;
        while (offset < bytes.length)
        {
            immutable byteValue = bytes[offset];
            if (plainText(byteValue))
            {
                ++offset;
                ++length;
                static if (hashed)
                    hash = advanceNameHash(hash, byteValue);
                continue;
            }
            immutable position = offset;
            if (byteValue == '"')
            {
                ++offset;
                token.end = position;
                token.length = length;
                token.hash = hash;
                return Error.init;
            }
            if (byteValue == '\\' && bytes.length - offset > 1)
            {
                immutable meaning = shortEscape(bytes[offset + 1]);
                if (meaning >= 0)
                {
                    offset += 2;
                    ++length;
                    static if (hashed)
                        hash = advanceNameHash(hash, meaning);
                    continue;
                }
            }
            const point = stringScalar(bytes, offset);
            if (!point.valid)
                return Error(Status.invalidArgument, "invalid JSON string", position);
            length += utf8Length(point.scalar);
            static if (hashed)
                hash = advanceNameHash(hash, point.scalar);
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
    KeyScope keys;
}

/// Validate and consume an unbound JSON value with an explicit container stack.
Error skipValue(ref scope Scanner scanner, uint parentDepth, bool checkDuplicates = true) nothrow @nogc
{
    if (scanner.keys !is null || !checkDuplicates || !scanner.options.rejectDuplicateKeys)
        return skipTree(scanner, parentDepth, checkDuplicates);
    KeyIndex index = void;
    index.clear();
    scope indexed = Scanner(scanner.bytes, scanner.options);
    indexed.offset = scanner.offset;
    indexed.keys = &index;
    const failure = skipTree(indexed, parentDepth, true);
    scanner.offset = indexed.offset;
    return failure;
}

private Error skipTree(ref scope Scanner scanner, uint parentDepth, bool checkDuplicates) nothrow @nogc
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
                closeKeys(scanner, container.keys);
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
        if (checkKeys && scanner.options.rejectDuplicateKeys && repeatedKey(scanner, container.keys,
                container.firstMember, keyOffset, key, depth))
            return Error(Status.invalidArgument, "duplicate JSON member", keyOffset);
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

/// Duplicate-key state of one open object.
struct KeyScope
{
    /// Fingerprints of the names checked in this object.
    ulong bloom;
    /// Logical index position of this object's first recorded name.
    uint base;
    /// Whether this object has recorded names in the shared index.
    bool open;
}

/// Exact name index for the objects open in one document, with stack discipline.
///
/// Each object records its names above those of its ancestors. When the bounded
/// ring is full, the oldest names are discarded; an object that lost names
/// rebuilds them from its validated source span before trusting the index again.
struct KeyIndex
{
    // A single object holds at most DecodeOptions.init.maxMembers names.
    private enum uint capacity = 1_024;
    private enum uint buckets = 512;

    private struct Entry
    {
        uint offset;
        ushort check;
        ushort distance;
    }

    private Entry[capacity] entries;
    private uint[buckets] heads;
    private uint origin;
    private uint top;
    // A plain byte keeps void initialization free of unsafe bit patterns.
    private ubyte ready;

    /// Reset the index without touching the entry storage.
    void clear() scope nothrow @nogc
    {
        origin = 0;
        top = 0;
        ready = 0;
    }

    private static ushort checkOf(uint hash) pure nothrow @nogc
    {
        return cast(ushort)(hash >> 16);
    }

    private static uint bucketOf(ushort check) pure nothrow @nogc
    {
        return check & (buckets - 1);
    }

    private void push(uint hash, size_t offset) scope nothrow @nogc
    {
        if (ready == 0)
        {
            heads[] = 0;
            ready = 1;
        }
        if (top - origin == capacity)
            ++origin;
        immutable check = checkOf(hash);
        immutable bucket = bucketOf(check);
        immutable previous = heads[bucket];
        ushort distance;
        if (previous != 0 && previous - 1 >= origin)
            distance = cast(ushort)(top - (previous - 1));
        entries[top % capacity] = Entry(cast(uint) offset, check, distance);
        heads[bucket] = top + 1;
        ++top;
    }

    private void popTo(uint base) scope nothrow @nogc
    {
        while (top > base && top > origin)
        {
            --top;
            const entry = entries[top % capacity];
            heads[bucketOf(entry.check)] = entry.distance == 0 ? 0 : top - entry.distance + 1;
        }
        if (top < origin)
            top = origin;
    }

    private bool contains(scope const(ubyte)[] bytes, TextToken key, uint base) const scope nothrow @nogc
    {
        if (ready == 0)
            return false;
        immutable check = checkOf(key.hash);
        uint link = heads[bucketOf(check)];
        while (link != 0)
        {
            immutable position = link - 1;
            if (position < base || position < origin || position >= top)
                return false;
            const entry = entries[position % capacity];
            if (entry.check == check && sameName(bytes, entry.offset, key))
                return true;
            if (entry.distance == 0)
                return false;
            link = position - entry.distance + 1;
        }
        return false;
    }
}

private bool sameName(scope const(ubyte)[] bytes, size_t offset, TextToken key) nothrow @nogc
{
    scope recorded = Scanner(bytes, DecodeOptions.init);
    recorded.offset = offset;
    TextToken earlier;
    return recorded.text(earlier).code == Status.ok && earlier.hash == key.hash && textTokensEqual(bytes, earlier, key);
}

/// Report whether a name repeats an earlier member of its object, then record it.
bool repeatedKey(ref scope Scanner scanner, ref KeyScope keys, size_t firstMember, size_t keyOffset,
        TextToken key, uint depth) nothrow @nogc
{
    immutable fingerprint = 1UL << (key.hash & 63);
    immutable possible = (keys.bloom & fingerprint) != 0;
    keys.bloom |= fingerprint;
    scope index = scanner.keys;
    if (index is null)
        return possible && earlierKey(scanner, firstMember, keyOffset, key, depth);

    if (!keys.open)
    {
        keys.open = true;
        keys.base = index.top;
    }
    bool complete = keys.base >= index.origin;
    if (possible)
    {
        if (!complete)
        {
            rebuildKeys(scanner, *index, keys, firstMember, keyOffset, depth);
            complete = true;
        }
        if (index.contains(scanner.bytes, key, keys.base))
            return true;
    }
    if (complete)
        index.push(key.hash, keyOffset);
    return false;
}

/// Release the names an object recorded once that object closes.
void closeKeys(ref scope Scanner scanner, ref KeyScope keys) nothrow @nogc
{
    if (keys.open && scanner.keys !is null)
        scanner.keys.popTo(keys.base);
    keys.open = false;
}

// Rescan an object's already validated members after older names were discarded.
private void rebuildKeys(ref scope Scanner scanner, ref scope KeyIndex index, ref KeyScope keys,
        size_t start, size_t end, uint depth) nothrow @nogc
{
    index.popTo(index.origin);
    keys.base = index.top;
    scope previous = Scanner(scanner.bytes, scanner.options);
    previous.offset = start;
    while (previous.offset < end)
    {
        previous.whitespace();
        if (previous.offset >= end)
            break;
        immutable keyOffset = previous.offset;
        TextToken earlier;
        if (previous.text(earlier).code != Status.ok)
            return;
        index.push(earlier.hash, keyOffset);
        previous.whitespace();
        if (!previous.take(':') || skipValue(previous, depth, false).code != Status.ok)
            return;
        previous.whitespace();
        if (!previous.take(','))
            break;
    }
}

private Error skipScalar(ref scope Scanner scanner) nothrow @nogc
{
    switch (scanner.peek())
    {
    case '"':
        TextToken text;
        return scanner.textValue(text);
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
