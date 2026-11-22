module flint.config.internal.sources;

import flint.arena : Error, Result, Status;

@safe:

package(flint.config) enum size_t maxConfigDepth = 16;
private enum size_t maxSourceBytes = 1_048_576;

// Decimal text of a line or column number, as std.conv.to!string writes it.
private string decimal(size_t value) pure nothrow
{
    char[20] digits;
    size_t start = digits.length;
    do
    {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    return digits[start .. $].idup;
}

// Code units of the well-formed UTF-8 sequence that starts at `text[index]`, or 0 when it is truncated, overlong,
// a surrogate, beyond U+10FFFF or a five- or six-unit form; the rules of std.utf.decode.
private size_t sequenceUnits(scope const(char)[] text, size_t index) pure nothrow @nogc
{
    static immutable uint[4] mask = [(1 << 7) - 1, (1 << 11) - 1, (1 << 16) - 1, (1 << 21) - 1];
    const ubyte lead = text[index];
    if (lead < 0x80)
        return 1;
    if ((lead & 0b1100_0000) != 0b1100_0000)
        return 0;
    uint scalar = lead;
    ubyte control = cast(ubyte)(lead << 1);
    foreach (i; 1 .. 4)
    {
        if (index + i == text.length || (text[index + i] & 0xC0) != 0x80)
            return 0;
        scalar = (scalar << 6) | (text[index + i] & 0x3F);
        control = cast(ubyte)(control << 1);
        if (control & 0x80)
            continue;
        scalar &= mask[i];
        const overlong = (scalar & ~mask[i - 1]) == 0;
        const surrogate = i == 2 && scalar >= 0xD800 && scalar <= 0xDFFF;
        return overlong || surrogate || (i == 3 && scalar > 0x10FFFF) ? 0 : i + 1;
    }
    return 0;
}

/// Whether the text is well-formed UTF-8, exactly as `std.utf.validate` accepts it.
package(flint.config) bool validUtf8(scope const(char)[] text) pure nothrow @nogc
{
    size_t index;
    while (index < text.length)
    {
        const units = sequenceUnits(text, index);
        if (units == 0)
            return false;
        index += units;
    }
    return true;
}

package(flint.config) struct Origin
{
    string name;
    string document;
    size_t offset = size_t.max;

    Error report(Status status, string key, string reason) const
    {
        const label = key.length == 0 ? "configuration" : "configuration key " ~ key;
        if (offset != size_t.max && offset <= document.length)
        {
            size_t line = 1;
            size_t column = 1;
            foreach (ch; document[0 .. offset])
            {
                if (ch == '\n')
                {
                    ++line;
                    column = 1;
                }
                else
                    ++column;
            }
            return Error(status, label ~ " in " ~ name ~ " at " ~ decimal(line) ~ ":" ~ decimal(column) ~ " " ~ reason,
                    offset);
        }
        return Error(status, label ~ " in " ~ name ~ " " ~ reason);
    }
}

package(flint.config) struct InputValue
{
    string text;
    Origin origin;
    bool json;
}

package(flint.config) alias Inputs = InputValue[string];

package(flint.config) struct SourceFile
{
    bool present;
    string text;
}

// The file name is a single component selected by the configuration loader.
private string sourcePath(string directory, string name)
{
    version (linux)
    {
        if (directory.length == 0)
            return name;
        const separator = directory[$ - 1] == '/' ? "" : "/";
        return directory ~ separator ~ name;
    }
    else
    {
        import std.path : buildPath;

        return buildPath(directory, name);
    }
}

package(flint.config) Result!SourceFile sourceFile(string directory, string name)
{
    import flint.config.sys.files : pathExists, readLimited;

    const path = sourcePath(directory, name);
    if (!pathExists(path))
        return Result!SourceFile(SourceFile.init);
    auto origin = Origin(name);
    string content;
    if (!readLimited(path, maxSourceBytes + 1, content))
        return Result!SourceFile(SourceFile.init, origin.report(Status.ioError, "", "could not be read"));
    if (content.length > maxSourceBytes)
        return Result!SourceFile(SourceFile.init, origin.report(Status.resourceExhausted, "", "exceeds 1 MiB"));
    if (content.length >= 3 && content[0 .. 3] == "\xEF\xBB\xBF")
        content = content[3 .. $];
    if (!validUtf8(content))
        return Result!SourceFile(SourceFile.init, origin.report(Status.invalidArgument, "", "contains invalid UTF-8"));
    return Result!SourceFile(SourceFile(true, content));
}

package(flint.config) bool keyComponent(scope const(char)[] name) pure nothrow @nogc
{
    if (name.length == 0)
        return false;
    foreach (ch; name)
    {
        const normalized = cast(char)(ch | 32);
        if (!(normalized >= 'a' && normalized <= 'z') && !(ch >= '0' && ch <= '9') && ch != '_' && ch != '-')
            return false;
    }
    return true;
}

/// Whether `text` begins with `prefix`, comparing code units as std.algorithm.searching.startsWith does for
/// two UTF-8 strings.
package(flint.config) bool hasPrefix(scope const(char)[] text, scope const(char)[] prefix) pure nothrow @nogc
{
    return text.length >= prefix.length && text[0 .. prefix.length] == prefix;
}

package(flint.config) string joinKey(string parent, string child)
{
    return parent.length == 0 ? child : parent ~ "." ~ child;
}

package(flint.config) Error putInput(ref Inputs entries, string key, InputValue input)
{
    if (key in entries)
        return input.origin.report(Status.conflict, key, "was specified more than once");
    entries[key] = input;
    return Error.init;
}

// Unicode White_Space, the set std.uni.isWhite tests.
private bool whiteSpace(dchar ch) pure nothrow @nogc
{
    if (ch < 0x80)
        return (ch >= 0x09 && ch <= 0x0D) || ch == 0x20;
    return ch == 0x85 || ch == 0xA0 || ch == 0x1680 || (ch >= 0x2000 && ch <= 0x200A) || ch == 0x2028
        || ch == 0x2029 || ch == 0x202F || ch == 0x205F || ch == 0x3000;
}

// Length of the well-formed UTF-8 sequence starting with `lead`.
private size_t sequenceLength(char lead) pure nothrow @nogc
{
    return lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4;
}

// Scalar of the well-formed UTF-8 sequence at `text[0 .. units]`.
private dchar scalarAt(scope const(char)[] text, size_t units) pure nothrow @nogc
{
    static immutable ubyte[5] leadMask = [0, 0x7F, 0x1F, 0x0F, 0x07];
    uint scalar = text[0] & leadMask[units];
    foreach (index; 1 .. units)
        scalar = (scalar << 6) | (text[index] & 0x3F);
    return cast(dchar) scalar;
}

// std.string.strip for text already validated as UTF-8: remove leading and trailing Unicode white space.
private inout(char)[] strip(return scope inout(char)[] text) pure nothrow @nogc
{
    size_t begin;
    while (begin < text.length)
    {
        const units = sequenceLength(text[begin]);
        if (!whiteSpace(scalarAt(text[begin .. $], units)))
            break;
        begin += units;
    }
    size_t end = text.length;
    while (end > begin)
    {
        size_t start = end - 1;
        while (start > begin && (text[start] & 0xC0) == 0x80)
            --start;
        if (!whiteSpace(scalarAt(text[start .. end], end - start)))
            break;
        end = start;
    }
    return text[begin .. end];
}

package(flint.config) Error readDotEnv(string text, ref Inputs entries)
{
    size_t start;
    foreach (index; 0 .. text.length + 1)
    {
        if (index < text.length && text[index] != '\n')
            continue;
        const line = strip(text[start .. index]);
        const origin = Origin(".env", text, start);
        start = index + 1;
        if (line.length == 0 || line[0] == '#')
            continue;

        size_t equals;
        while (equals < line.length && line[equals] != '=')
            ++equals;
        const key = strip(line[0 .. equals]);
        if (equals == line.length || !keyComponent(key))
            return origin.report(Status.invalidArgument, "", "requires KEY=VALUE");
        const raw = strip(line[equals + 1 .. $]);
        string value;
        if (!environmentValue(raw, value))
            return origin.report(Status.invalidArgument, key, "has invalid quoting or escapes");
        const failure = putInput(entries, key, InputValue(value, origin));
        if (failure.code != Status.ok)
            return failure;
    }
    return Error.init;
}

private bool environmentValue(string raw, out string value)
{
    if (raw.length == 0 || (raw[0] != '\'' && raw[0] != '"'))
    {
        value = raw;
        return true;
    }
    const quote = raw[0];
    char[] decoded;
    for (size_t index = 1; index < raw.length; ++index)
    {
        const ch = raw[index];
        if (ch == quote)
        {
            if (index + 1 != raw.length)
                return false;
            value = decoded.idup;
            return true;
        }
        if (ch != '\\' || quote != '"')
        {
            decoded ~= ch;
            continue;
        }
        if (++index >= raw.length)
            return false;
        const escaped = escapeCharacter(raw[index]);
        if (escaped == '\0')
            return false;
        decoded ~= escaped;
    }
    return false;
}

private char escapeCharacter(char input) pure nothrow @nogc
{
    switch (input)
    {
    case 'n':
        return '\n';
    case 'r':
        return '\r';
    case 't':
        return '\t';
    case '\\':
    case '"':
        return input;
    default:
        return '\0';
    }
}

package(flint.config) Error readJson(string name, string text, ref Inputs entries)
{
    auto parser = ObjectReader(name, text);
    parser.skipSpace();
    const failure = parser.object("", 1, entries);
    if (failure.code != Status.ok)
        return failure;
    parser.skipSpace();
    return parser.cursor == text.length ? Error.init : parser.invalid("", "has trailing input");
}

private struct ObjectReader
{
    string name;
    string text;
    size_t cursor;

    private struct KeyBox
    {
        string key;
    }

    private struct IgnoredValue
    {
    }

    private Origin origin(size_t start) const
    {
        return Origin(name, text, start);
    }

    private Error invalid(string key, string reason) const
    {
        return origin(cursor).report(Status.invalidArgument, key, reason);
    }

    private char peek() const pure nothrow @nogc
    {
        return cursor < text.length ? text[cursor] : '\0';
    }

    void skipSpace() pure nothrow @nogc
    {
        while (peek() == ' ' || peek() == '\t' || peek() == '\r' || peek() == '\n')
            ++cursor;
    }

    private bool take(char ch) pure nothrow @nogc
    {
        if (cursor >= text.length || text[cursor] != ch)
            return false;
        ++cursor;
        return true;
    }

    private bool skipString() pure nothrow @nogc
    {
        if (!take('"'))
            return false;
        while (cursor < text.length)
        {
            const ch = text[cursor++];
            if (ch == '"')
                return true;
            if (ch == '\\' && cursor < text.length)
                ++cursor;
        }
        return false;
    }

    Error object(string parent, size_t depth, ref Inputs entries)
    {
        if (depth > maxConfigDepth + 1)
            return origin(cursor).report(Status.resourceExhausted, parent, "exceeds the nesting limit");
        const opening = cursor;
        if (!take('{'))
            return invalid(parent, "must be a JSON object");
        skipSpace();
        if (take('}'))
        {
            if (parent.length != 0)
                return putInput(entries, parent, InputValue("{}", origin(opening), true));
            return Error.init;
        }

        bool[string] seen;
        for (;;)
        {
            skipSpace();
            const keyOffset = cursor;
            const readKey = keyAndColon(parent, seen);
            if (!readKey.ok)
                return readKey.error;
            skipSpace();
            const key = readKey.value;
            const failure = peek() == '{' ? object(key, depth + 1, entries) : readLeaf(key, keyOffset, depth, entries);
            if (failure.code != Status.ok)
                return failure;
            skipSpace();
            if (take('}'))
                return Error.init;
            if (!take(','))
                return invalid(parent, "requires a comma or closing brace");
        }
    }

    private Result!string keyAndColon(string parent, ref bool[string] seen)
    {
        import flint.serde.owned : deserialize;

        const start = cursor;
        if (!skipString())
            return Result!string(null, invalid(parent, "requires a quoted JSON key"));
        const keyBox = deserialize!KeyBox("{\"key\":" ~ text[start .. cursor] ~ "}");
        if (!keyBox.ok)
            return Result!string(null, invalid(parent, "has an invalid JSON key"));
        const part = keyBox.value.key;
        if (!keyComponent(part))
            return Result!string(null, origin(start).report(Status.invalidArgument, parent,
                    "has an invalid key component"));
        const key = joinKey(parent, part);
        if (part in seen)
            return Result!string(null, origin(start).report(Status.conflict, key, "was specified more than once"));
        seen[part] = true;
        skipSpace();
        if (!take(':'))
            return Result!string(null, invalid(key, "requires a value"));
        return Result!string(key);
    }

    private Error readLeaf(string key, size_t keyOffset, size_t depth, ref Inputs entries)
    {
        import flint.serde : DecodeOptions, UnknownFields;
        import flint.serde.owned : deserialize;

        const start = cursor;
        if (!skipValue(depth))
            return invalid(key, "has invalid or excessively nested JSON");
        auto limits = DecodeOptions.init;
        limits.unknownFields = UnknownFields.ignore;
        if (!deserialize!IgnoredValue("{\"value\":" ~ text[start .. cursor] ~ "}", limits).ok)
            return invalid(key, "has an invalid JSON value");
        return putInput(entries, key, InputValue(text[start .. cursor], origin(keyOffset), true));
    }

    private bool skipValue(size_t depth) pure nothrow @nogc
    {
        if (peek() == '"')
            return skipString();
        if (peek() == '[' || peek() == '{')
            return skipContainer(depth);
        const start = cursor;
        while (cursor < text.length && !tokenBoundary(peek()))
            ++cursor;
        return cursor > start;
    }

    private bool skipContainer(size_t depth) pure nothrow @nogc
    {
        char[maxConfigDepth + 1] closing;
        size_t level = depth;
        do
        {
            if (peek() == '"')
            {
                if (!skipString())
                    return false;
                continue;
            }
            const ch = text[cursor++];
            if (ch == '[' || ch == '{')
            {
                if (level == closing.length)
                    return false;
                closing[level++] = ch == '[' ? ']' : '}';
            }
            if (ch == ']' || ch == '}')
            {
                if (level == depth || ch != closing[--level])
                    return false;
            }
        }
        while (level > depth && cursor < text.length);
        return level == depth;
    }
}

private bool tokenBoundary(char ch) pure nothrow @nogc
{
    return ch == ',' || ch == '}' || ch == ']' || ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t';
}

version (unittest)
{
    @("config text helpers match the Phobos functions they replace")
    unittest
    {
        import std.conv : to;
        import std.string : stdStrip = strip;
        import std.uni : isWhite;
        import std.utf : UTFException, validate;

        foreach (dchar ch; 0 .. 0x110000)
            assert(whiteSpace(ch) == isWhite(ch));
        foreach (value; [0UL, 1, 9, 10, 4_294_967_296, ulong.max])
            assert(decimal(cast(size_t) value) == (cast(size_t) value).to!string);
        foreach (text; [
            "", " ", "a", " a ", "\t\u00A0x\u3000\u2028", "\u0085 key = value \u202F\u205F", "\u1680",
            "x\u2000\u200A", "\u200B x \u200B", "é ", " ü", "\U0001F600 \U0001F600", "\r\n"
        ])
            assert(strip(text) == stdStrip(text));

        static bool phobosValid(scope const(char)[] text) @safe
        {
            try
                validate(text);
            catch (UTFException)
                return false;
            return true;
        }

        char[5] buffer;
        static immutable ubyte[] edges = [
            0x00, 0x41, 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xC1, 0xC2, 0xDF, 0xE0,
            0xED, 0xEF, 0xF0, 0xF4, 0xF5, 0xF7, 0xF8, 0xFB, 0xFC, 0xFE, 0xFF
        ];
        foreach (first; 0 .. 256)
            foreach (second; 0 .. 256)
            {
                buffer[0] = cast(char) first;
                buffer[1] = cast(char) second;
                assert(validUtf8(buffer[0 .. 1]) == phobosValid(buffer[0 .. 1]));
                assert(validUtf8(buffer[0 .. 2]) == phobosValid(buffer[0 .. 2]));
            }
        foreach (a; edges)
            foreach (b; edges)
                foreach (c; edges)
                    foreach (d; edges)
                    {
                        buffer[0 .. 4] = [cast(char) a, cast(char) b, cast(char) c, cast(char) d];
                        assert(validUtf8(buffer[0 .. 3]) == phobosValid(buffer[0 .. 3]));
                        assert(validUtf8(buffer[0 .. 4]) == phobosValid(buffer[0 .. 4]));
                        buffer[4] = 'z';
                        assert(validUtf8(buffer[0 .. 5]) == phobosValid(buffer[0 .. 5]));
                    }
    }
}
