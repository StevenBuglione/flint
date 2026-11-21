/// Scoped inspection of validated JSON objects and arrays.
module flint.serde.json_visit;

import flint.arena : Error, Status;
import flint.serde.internal.json_codec : bounded;
import flint.serde.internal.json_scan : Scanner, TextToken, copyText, skipValue, textEquals;
import flint.serde.internal.types : DecodeOptions;

@safe:

/// A borrowed JSON member name, with comparison over decoded UTF-8.
struct JsonMemberName
{
    private const(ubyte)[] document;
    private TextToken token;

    private this(return scope const(ubyte)[] document, TextToken token) nothrow @nogc
    {
        this.document = document;
        this.token = token;
    }

    /// Compare the semantic UTF-8 name, including escaped forms.
    bool isName(scope const(char)[] expected) const scope nothrow @nogc
    {
        return token.length == expected.length && textEquals(document, token, cast(const(ubyte)[]) expected);
    }

    /// Number of decoded UTF-8 bytes.
    size_t length() const scope pure nothrow @nogc
    {
        return token.length;
    }

    /// Copy the complete decoded name into caller storage.
    bool copyName(scope ubyte[] output) const scope nothrow @nogc
    {
        return token.length <= output.length && copyText(document, token, output[0 .. token.length]);
    }
}

/// Visit one checked object field. Both arguments are borrowed for the call.
alias JsonMemberVisitor = Error delegate(scope JsonMemberName name, scope const(ubyte)[] value) @safe nothrow @nogc;
/// Inspect a decoded member name and the byte range of its checked JSON value.
alias JsonMemberRangeVisitor = Error delegate(scope JsonMemberName name, size_t offset, size_t length) @safe nothrow @nogc;
/// Visit one checked value in array order.
alias JsonElementVisitor = Error delegate(scope const(ubyte)[] value) @safe nothrow @nogc;

/// Validate the entire document, then visit object fields in source order.
Error visitJsonObject(scope const(ubyte)[] input, scope JsonMemberVisitor visitor,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc
{
    return visit(input, visitor, options);
}

/// Validate an object before visiting each raw value range. An explicit byte limit may be up to 4 MiB.
Error visitJsonObjectRanges(scope const(ubyte)[] input, scope JsonMemberRangeVisitor visitor,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc
{
    return visit(input, visitor, options);
}

/// Validate the entire document, then visit array values in source order.
Error visitJsonArray(scope const(ubyte)[] input, scope JsonElementVisitor visitor,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc
{
    return visit(input, visitor, options);
}

private Error validated(scope const(ubyte)[] input, ubyte opening, DecodeOptions options) nothrow @nogc
{
    if (input.length > options.maxBytes)
        return Error(Status.resourceExhausted, "JSON document exceeds its byte limit", options.maxBytes);
    scope check = Scanner(input, options);
    check.whitespace();
    if (check.peek() != opening)
        return Error(Status.invalidArgument, "unexpected JSON document shape", check.offset);
    const status = skipValue(check, 0);
    if (status.code != Status.ok)
        return status;
    check.whitespace();
    return check.offset == input.length ? Error.init : Error(Status.invalidArgument,
            "trailing JSON bytes", check.offset);
}

private Error visit(Visitor)(scope const(ubyte)[] json, scope Visitor visitor, DecodeOptions limits) nothrow @nogc
{
    if (visitor is null)
        return Error(Status.invalidArgument, "missing JSON visitor");
    enum ranges = is(Visitor == JsonMemberRangeVisitor);
    enum maximumInspection = 4 * 1024 * 1024;
    const requested = limits.maxBytes;
    limits = bounded(limits);
    static if (ranges)
        limits.maxBytes = requested < maximumInspection ? requested : maximumInspection;
    enum object = ranges || is(Visitor == JsonMemberVisitor);
    enum opening = cast(ubyte)(object ? '{' : '[');
    enum closing = cast(ubyte)(object ? '}' : ']');
    const accepted = validated(json, opening, limits);
    if (accepted.code != Status.ok)
        return accepted;
    scope cursor = Scanner(json, limits);
    cursor.whitespace();
    ++cursor.offset;
    cursor.whitespace();
    while (!cursor.take(closing))
    {
        static if (object)
        {
            TextToken key;
            const tokenized = cursor.text(key);
            if (tokenized.code != Status.ok)
                return tokenized;
            cursor.whitespace();
            if (!cursor.take(':'))
                return Error(Status.invalidArgument, "expected a JSON member colon", cursor.offset);
            cursor.whitespace();
            scope const name = JsonMemberName(json, key);
        }
        const start = cursor.offset;
        const parsed = skipValue(cursor, 1, false);
        if (parsed.code != Status.ok)
            return parsed;
        static if (ranges)
            const visited = visitor(name, start, cursor.offset - start);
        else static if (object)
            const visited = visitor(name, json[start .. cursor.offset]);
        else
            const visited = visitor(json[start .. cursor.offset]);
        if (visited.code != Status.ok)
            return visited;
        cursor.whitespace();
        if (cursor.peek() != closing && !cursor.take(','))
            return Error(Status.invalidArgument, "expected a JSON member separator", cursor.offset);
        cursor.whitespace();
    }
    return Error.init;
}
