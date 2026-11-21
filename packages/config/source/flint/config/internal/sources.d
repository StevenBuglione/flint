module flint.config.internal.sources;

import flint.arena : Error, Result, Status;
import flint.serde : DecodeOptions, UnknownFields;
import flint.serde.owned : deserialize;
import std.conv : to;
import std.file : exists, read;
import std.string : strip;
import std.utf : validate;

@safe:

package(flint.config) enum size_t maxConfigDepth = 16;
private enum size_t maxSourceBytes = 1_048_576;

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
            return Error(status,
                    label ~ " in " ~ name ~ " at " ~ line.to!string ~ ":" ~ column.to!string ~ " " ~ reason, offset);
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
        import std.path : dirSeparator, isDirSeparator;

        if (directory.length == 0)
            return name;
        const separator = isDirSeparator(directory[$ - 1]) ? "" : dirSeparator;
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
    const path = sourcePath(directory, name);
    if (!exists(path))
        return Result!SourceFile(SourceFile.init);
    auto origin = Origin(name);
    string content;
    try
        content = (cast(const(char)[]) read(path, maxSourceBytes + 1)).idup;
    catch (Exception)
        return Result!SourceFile(SourceFile.init, origin.report(Status.ioError, "", "could not be read"));
    if (content.length > maxSourceBytes)
        return Result!SourceFile(SourceFile.init, origin.report(Status.resourceExhausted, "", "exceeds 1 MiB"));
    if (content.length >= 3 && content[0 .. 3] == "\xEF\xBB\xBF")
        content = content[3 .. $];
    try
        validate(content);
    catch (Exception)
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
