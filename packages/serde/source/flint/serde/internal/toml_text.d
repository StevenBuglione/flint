/// TOML 1.0 key and string lexing, including multiline and literal forms.
module flint.serde.internal.toml_text;

import flint.arena : Error, Status;
import flint.serde.internal.json_scan : Codepoint, readUtf8, utf8Scalar, writeScalar;
import flint.serde.internal.writer : Writer;

@safe:

/// A source token within the bounded TOML document.
struct Span
{
    /// Inclusive starting byte.
    uint first;
    /// Exclusive ending byte.
    uint last;
}

/// Recognize a byte of a TOML bare key.
bool bare(ubyte byteValue) nothrow @nogc
{
    return (byteValue >= '0' && byteValue <= '9') || (byteValue >= 'a' && byteValue <= 'z')
        || (byteValue >= 'A' && byteValue <= 'Z') || byteValue == '-' || byteValue == '_';
}

/// Recognize a horizontal TOML whitespace byte.
bool horizontal(ubyte byteValue) nothrow @nogc
{
    return byteValue == ' ' || byteValue == '\t';
}

private struct StringPart
{
    uint scalar;
    bool ended;
    Error error;
}

private struct StringCursor
{
    size_t offset;
    uint pendingQuotes;
    ubyte delimiter;
    bool multiline;
    bool closing;

    bool begin(scope const(ubyte)[] bytes, size_t first, bool allowMultiline) nothrow @nogc
    {
        if (first == bytes.length)
            return false;
        delimiter = bytes[first];
        if (delimiter != '"' && delimiter != '\'')
            return false;
        offset = first + 1;
        if (bytes.length - offset >= 2 && bytes[offset] == delimiter && bytes[offset + 1] == delimiter)
        {
            if (!allowMultiline)
                return false;
            multiline = true;
            offset += 2;
            lineEnding(bytes);
        }
        return true;
    }

    Error next(scope const(ubyte)[] bytes, out uint scalar, out bool ended) nothrow @nogc
    {
        immutable first = offset;
        if (closing)
            return closeQuotes(scalar, ended);
        while (offset < bytes.length)
        {
            immutable byteValue = bytes[offset];
            if (byteValue == delimiter)
                return readQuotes(bytes, scalar, ended);
            if (byteValue == '\\' && delimiter == '"')
            {
                ++offset;
                if (multiline && escapeEnding(bytes))
                    continue;
                if (!escape(bytes, scalar))
                    return invalid(first);
                return Error.init;
            }
            if (multiline && lineEnding(bytes))
            {
                scalar = '\n';
                return Error.init;
            }
            return rawScalar(bytes, scalar, first);
        }
        return invalid(first);
    }

    private Error rawScalar(scope const(ubyte)[] bytes, out uint scalar, size_t first) nothrow @nogc
    {
        if (!utf8Scalar(bytes, offset, scalar) || (scalar < 0x20 && scalar != '\t') || scalar == 0x7f)
            return invalid(first);
        return Error.init;
    }

    private Error closeQuotes(out uint scalar, out bool ended) nothrow @nogc
    {
        if (pendingQuotes == 0)
            ended = true;
        else
        {
            --pendingQuotes;
            scalar = delimiter;
        }
        return Error.init;
    }

    StringPart part(scope const(ubyte)[] bytes) nothrow @nogc
    {
        StringPart decoded;
        decoded.error = next(bytes, decoded.scalar, decoded.ended);
        return decoded;
    }

    private Error readQuotes(scope const(ubyte)[] bytes, out uint scalar, out bool ended) nothrow @nogc
    {
        size_t count = 1;
        if (multiline)
        {
            while (count < bytes.length - offset && bytes[offset + count] == delimiter)
                ++count;
            if (count > 5)
                return invalid(offset);
            if (count >= 3)
            {
                offset += count;
                pendingQuotes = cast(uint) count - 3;
                if (pendingQuotes != 0)
                {
                    --pendingQuotes;
                    scalar = delimiter;
                    closing = true;
                }
                else
                    ended = true;
                return Error.init;
            }
        }
        else
        {
            ++offset;
            ended = true;
            return Error.init;
        }
        ++offset;
        scalar = delimiter;
        return Error.init;
    }

    private Error invalid(size_t position) const nothrow @nogc
    {
        return Error(Status.invalidArgument, "invalid TOML string", position);
    }

    private bool lineEnding(scope const(ubyte)[] bytes) nothrow @nogc
    {
        if (offset == bytes.length)
            return false;
        if (bytes[offset] == '\n')
        {
            ++offset;
            return true;
        }
        if (bytes[offset] == '\r' && bytes.length - offset > 1 && bytes[offset + 1] == '\n')
        {
            offset += 2;
            return true;
        }
        return false;
    }

    private bool escapeEnding(scope const(ubyte)[] bytes) nothrow @nogc
    {
        immutable initial = offset;
        while (offset < bytes.length && horizontal(bytes[offset]))
            ++offset;
        if (!lineEnding(bytes))
        {
            offset = initial;
            return false;
        }
        while (offset < bytes.length)
        {
            if (horizontal(bytes[offset]))
                ++offset;
            else if (!lineEnding(bytes))
                break;
        }
        return true;
    }

    private bool escape(scope const(ubyte)[] bytes, out uint scalar) nothrow @nogc
    {
        if (offset == bytes.length)
            return false;
        immutable byteValue = bytes[offset++];
        switch (byteValue)
        {
        case '\\', '"':
            scalar = byteValue;
            return true;
        case 'b':
            scalar = '\b';
            return true;
        case 't':
            scalar = '\t';
            return true;
        case 'n':
            scalar = '\n';
            return true;
        case 'f':
            scalar = '\f';
            return true;
        case 'r':
            scalar = '\r';
            return true;
        case 'u', 'U':
            return unicodeEscape(bytes, byteValue == 'u' ? 4 : 8, scalar);
        default:
            return false;
        }
    }

    private bool unicodeEscape(scope const(ubyte)[] bytes, uint count, out uint scalar) nothrow @nogc
    {
        if (count > bytes.length - offset)
            return false;
        foreach (index; 0 .. count)
        {
            immutable byteValue = bytes[offset++];
            scalar <<= 4;
            if (byteValue >= '0' && byteValue <= '9')
                scalar |= byteValue - '0';
            else if (byteValue >= 'a' && byteValue <= 'f')
                scalar |= byteValue - 'a' + 10;
            else if (byteValue >= 'A' && byteValue <= 'F')
                scalar |= byteValue - 'A' + 10;
            else
                return false;
        }
        return scalar <= 0x10_ffff && (scalar < 0xd800 || scalar > 0xdfff);
    }
}

/// Read and validate one quoted token, keeping its source span.
Error quotedSpan(scope const(ubyte)[] bytes, ref size_t offset, bool allowMultiline, out Span token) nothrow @nogc
{
    StringCursor cursor;
    if (!cursor.begin(bytes, offset, allowMultiline))
        return Error(Status.invalidArgument, "expected a quoted TOML string", offset);
    token.first = cast(uint) offset;
    for (;;)
    {
        const decoded = cursor.part(bytes);
        if (decoded.error.code != Status.ok)
            return decoded.error;
        if (decoded.ended)
            break;
    }
    token.last = cast(uint) cursor.offset;
    offset = cursor.offset;
    return Error.init;
}

/// Read and validate one bare or quoted path component.
Error keySpan(scope const(ubyte)[] bytes, ref size_t offset, out Span token) nothrow @nogc
{
    if (offset < bytes.length && (bytes[offset] == '"' || bytes[offset] == '\''))
        return quotedSpan(bytes, offset, false, token);
    immutable first = offset;
    while (offset < bytes.length && bare(bytes[offset]))
        ++offset;
    if (offset == first)
        return Error(Status.invalidArgument, "expected a TOML key", offset);
    token = Span(cast(uint) first, cast(uint) offset);
    return Error.init;
}

private struct KeyCursor
{
    StringCursor quoted;
    size_t offset;
    bool bareKey;

    this(scope const(ubyte)[] bytes, bool allowMultiline = false) nothrow @nogc
    {
        bareKey = !quoted.begin(bytes, 0, allowMultiline);
    }

    bool next(scope const(ubyte)[] bytes, out uint scalar) nothrow @nogc
    {
        if (bareKey)
            return utf8Scalar(bytes, offset, scalar);
        const decoded = quoted.part(bytes);
        scalar = decoded.scalar;
        return decoded.error.code == Status.ok && !decoded.ended;
    }
}

// The raw contents of a bare, literal or escape-free basic key equal its decoded name.
private bool verbatimKey(scope const(ubyte)[] key, out size_t begin, out size_t end) nothrow @nogc
{
    end = key.length;
    if (key.length == 0 || (key[0] != '"' && key[0] != '\''))
        return true;
    if (key.length < 2)
        return false;
    begin = 1;
    --end;
    if (key[0] == '\'')
        return true;
    foreach (byteValue; key[begin .. end])
    {
        if (byteValue == '\\')
            return false;
    }
    return true;
}

// Byte equality without the C memcmp that slice comparison needs in BetterC.
private bool sameBytes(scope const(ubyte)[] left, scope const(ubyte)[] right) pure nothrow @nogc
{
    if (left.length != right.length)
        return false;
    foreach (index, byteValue; left)
    {
        if (byteValue != right[index])
            return false;
    }
    return true;
}

/// Hash an already validated TOML key component by its decoded Unicode scalars.
ushort keyHash(scope const(ubyte)[] key) nothrow @nogc
{
    uint hash = 2_166_136_261;
    KeyCursor cursor = KeyCursor(key);
    Codepoint point;
    while (cursor.next(key, point.scalar))
        hash = (hash ^ point.scalar) * 16_777_619;
    return cast(ushort)(hash ^ (hash >> 16));
}

/// Compare two already validated TOML key components.
bool sameKey(scope const(ubyte)[] first, scope const(ubyte)[] second) nothrow @nogc
{
    size_t leftFirst, leftLast, rightFirst, rightLast;
    if (verbatimKey(first, leftFirst, leftLast) && verbatimKey(second, rightFirst, rightLast))
        return sameBytes(first[leftFirst .. leftLast], second[rightFirst .. rightLast]);
    KeyCursor left = KeyCursor(first);
    KeyCursor right = KeyCursor(second);
    Codepoint leftPoint;
    Codepoint rightPoint;
    while (left.next(first, leftPoint.scalar))
    {
        if (!right.next(second, rightPoint.scalar) || leftPoint.scalar != rightPoint.scalar)
            return false;
    }
    return !right.next(second, rightPoint.scalar);
}

/// Compare a TOML key with its decoded UTF-8 descriptor name.
bool keyEquals(scope const(ubyte)[] key, scope const(ubyte)[] name, bool allowMultiline = false) nothrow @nogc
{
    KeyCursor cursor = KeyCursor(key, allowMultiline);
    size_t offset;
    Codepoint keyPoint;
    while (cursor.next(key, keyPoint.scalar))
    {
        const namePoint = readUtf8(name, offset);
        if (!namePoint.valid || keyPoint.scalar != namePoint.scalar)
            return false;
    }
    return offset == name.length;
}

/// Materialize an already validated quoted value in the requested sink.
void emitText(ref scope Writer writer, scope const(ubyte)[] token) nothrow @nogc
{
    StringCursor cursor;
    if (!cursor.begin(token, 0, true))
    {
        writer.fail(Status.invalidArgument, "expected a quoted TOML value");
        return;
    }
    for (;;)
    {
        const decoded = cursor.part(token);
        if (decoded.error.code != Status.ok)
        {
            writer.fail(decoded.error.code, decoded.error.message);
            return;
        }
        if (decoded.ended)
            return;
        ubyte[4] bytes;
        const length = writeScalar(decoded.scalar, bytes);
        writer.append(bytes[0 .. length]);
    }
}
