/// Typed JSON encoding and transactional, bounded decoding.
module flint.serde.internal.json_codec;

import flint.arena : Buffer, Error, RequestArena, Result, Status, Text;
import flint.serde.internal.decimal : parseDecimal, writeDecimal;
import flint.serde.internal.fields : JsonFields;
import flint.serde.internal.json_scan : KeyIndex, KeyScope, Scanner, TextToken, NumberToken,
    closeKeys, copyText, repeatedKey, skipValue, textEquals;
import flint.serde.internal.types : DecodeOptions, EncodeOptions, UnknownFields;
import flint.serde.internal.writer : Writer, writeArenaBuffer;
import std.traits : Unqual;

@safe:

private const(size_t) noProperty = size_t.max;

/// Enforce library bounds even when callers provide greater option values.
DecodeOptions bounded(DecodeOptions options) pure nothrow @nogc
{
    const limits = DecodeOptions.init;
    if (options.maxDepth > limits.maxDepth)
        options.maxDepth = limits.maxDepth;
    if (options.maxMembers > limits.maxMembers)
        options.maxMembers = limits.maxMembers;
    if (options.maxBytes > limits.maxBytes)
        options.maxBytes = limits.maxBytes;
    return options;
}

/// Sizing and materialization state shared by the typed arena decoders.
struct AllocationPlan
{
    /// The complete input has already passed validation and allocation preflight.
    bool materialize;
    /// At least one decoded output field needs a live arena handle.
    bool storesBytes;
    /// Sum of the required byte allocations in the validation pass.
    size_t bytes;
}

/// Parse and size the complete input before modifying the caller's arena.
Error readJson(T, bool normalized = false)(scope const(ubyte)[] input, ref T destination,
        ref scope RequestArena arena, DecodeOptions options) nothrow @nogc
{
    options = bounded(options);
    const byteLimit = normalized ? DecodeOptions.init.maxBytes * 6 : options.maxBytes;
    if (input.length > byteLimit)
        return Error(Status.resourceExhausted, "JSON document exceeds its byte limit", byteLimit);

    AllocationPlan plan;
    T temporary;
    auto failure = readDocument(input, temporary, arena, options, plan);
    if (failure.code != Status.ok)
        return failure;
    if (!plan.storesBytes)
    {
        destination = temporary;
        return Error.init;
    }
    const usage = arena.stats();
    if (plan.bytes > usage.capacity - usage.used)
        return Error(Status.outOfMemory, "arena capacity exhausted");

    plan.materialize = true;
    failure = readDocument(input, temporary, arena, options, plan);
    if (failure.code == Status.ok)
        destination = temporary;
    return failure;
}

/// Decode native owned fields using the same scanner and descriptor semantics.
Error readOwnedJson(T)(scope const(ubyte)[] input, ref T target, DecodeOptions options)
{
    options = bounded(options);
    if (input.length > options.maxBytes)
        return Error(Status.resourceExhausted, "JSON document exceeds its byte limit", options.maxBytes);

    T temporary;
    RequestArena unusedArena;
    AllocationPlan plan;
    auto failure = readDocument!(T, true)(input, temporary, unusedArena, options, plan);
    if (failure.code == Status.ok)
        target = temporary;
    return failure;
}

private Error readDocument(T, bool owned = false)(scope const(ubyte)[] input, ref T target,
        ref scope RequestArena arena, DecodeOptions options, ref AllocationPlan plan)
{
    KeyIndex keys = void;
    keys.clear();
    scope scanner = Scanner(input, options);
    scanner.keys = &keys;
    auto failure = readValue!(T, owned)(scanner, target, arena, plan, 0);
    if (failure.code != Status.ok)
        return failure;
    scanner.whitespace();
    if (scanner.offset != input.length)
        return Error(Status.invalidArgument, "trailing JSON input", scanner.offset);
    return Error.init;
}

private enum signedInteger(T) = is(T == byte) || is(T == short) || is(T == int) || is(T == long);
private enum unsignedInteger(T) = is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong);

private Error readValue(T, bool owned)(ref scope Scanner scanner, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, uint depth)
{
    scanner.whitespace();
    static if (is(T == bool))
        return readBoolean(scanner, target);
    else static if (signedInteger!T || unsignedInteger!T)
        return readInteger(scanner, target);
    else static if (is(T == float) || is(T == double))
        return readFloat(scanner, target);
    else static if (is(T == enum))
        return readEnum(scanner, target);
    else static if (is(T == Text) || is(T == Buffer))
    {
        static assert(!owned, "native owned DTOs cannot retain arena handles");
        return readArenaField(scanner, target, arena, plan);
    }
    else static if (owned && (is(T == char[]) || is(T == const(char)[]) || is(T == immutable(char)[])))
        return readOwnedString(scanner, target);
    else static if (owned && is(T == Element[], Element))
        return readOwnedArray(scanner, target, arena, plan, depth);
    else static if (is(T == Element[extent], Element, size_t extent))
        return readArray!(T, extent, owned)(scanner, target, arena, plan, depth);
    else static if (is(T == struct))
        return readObject!(T, owned)(scanner, target, arena, plan, depth);
    else
        static assert(false, "unsupported hot JSON output type " ~ T.stringof);
}

private Error readBoolean(ref scope Scanner scanner, ref bool target) nothrow @nogc
{
    if (scanner.literal(cast(const(ubyte)[]) "true"))
        target = true;
    else if (scanner.literal(cast(const(ubyte)[]) "false"))
        target = false;
    else
        return Error(Status.invalidArgument, "expected a JSON boolean", scanner.offset);
    return Error.init;
}

private Error readArenaField(T)(ref scope Scanner scanner, ref T target, ref scope RequestArena arena,
        ref AllocationPlan plan) nothrow @nogc
{
    Buffer value;
    auto failure = readBytes(scanner, value, arena, plan);
    if (failure.code != Status.ok)
        return failure;
    static if (is(T == Text))
        target = Text(value);
    else
        target = value;
    return Error.init;
}

private Error readInteger(T)(ref scope Scanner scanner, ref T target) nothrow @nogc
{
    NumberToken token;
    auto failure = scanner.number(token);
    if (failure.code != Status.ok)
        return failure;
    if (token.fractional)
        return Error(Status.invalidArgument, "expected an integer JSON value", token.start);

    immutable negative = scanner.bytes[token.start] == '-';
    ulong limit = T.max;
    static if (signedInteger!T)
    {
        if (negative)
            ++limit;
    }
    ulong value;
    immutable firstDigit = token.start + (negative ? 1 : 0);
    foreach (byteValue; scanner.bytes[firstDigit .. token.end])
    {
        immutable digitValue = cast(uint)(byteValue - '0');
        if (value > (limit - digitValue) / 10)
            return Error(Status.invalidArgument, "JSON integer is outside its field range", token.start);
        value = value * 10 + digitValue;
    }
    if (negative && value != 0)
    {
        static if (signedInteger!T)
            target = cast(T)(-cast(long)(value - 1) - 1);
        else
            return Error(Status.invalidArgument, "negative JSON integer in unsigned field", token.start);
    }
    else
        target = cast(T) value;
    return Error.init;
}

private Error readFloat(T)(ref scope Scanner scanner, ref T target) nothrow @nogc
{
    NumberToken token;
    auto failure = scanner.number(token);
    if (failure.code != Status.ok)
        return failure;
    if (!parseDecimal(scanner.bytes[token.start .. token.end], target))
        return Error(Status.invalidArgument, "JSON number is outside its floating point range", token.start);
    return Error.init;
}

private Error readEnum(T)(ref scope Scanner scanner, ref T target) nothrow @nogc
{
    TextToken token;
    auto failure = scanner.textValue(token);
    if (failure.code != Status.ok)
        return failure;
    static foreach (member; __traits(allMembers, T))
    {
        if (textEquals(scanner.bytes, token, cast(const(ubyte)[]) member))
        {
            target = __traits(getMember, T, member);
            return Error.init;
        }
    }
    return Error(Status.invalidArgument, "unknown JSON enum value", token.start);
}

private Error readBytes(ref scope Scanner scanner, ref Buffer target, ref scope RequestArena arena,
        ref AllocationPlan plan) nothrow @nogc
{
    TextToken token;
    auto failure = scanner.textValue(token);
    if (failure.code != Status.ok)
        return failure;
    if (!plan.materialize)
    {
        if (token.length > size_t.max - plan.bytes)
            return Error(Status.resourceExhausted, "decoded JSON byte count overflows", token.start);
        plan.bytes += token.length;
        plan.storesBytes = true;
        return Error.init;
    }

    auto allocation = arena.allocate(token.length, 1);
    if (!allocation.ok())
        return allocation.error;
    bool copied;
    immutable status = arena.write(allocation.value, (scope ubyte[] output) @safe nothrow @nogc {
        copied = copyText(scanner.bytes, token, output);
    });
    if (status != Status.ok || !copied)
        return Error(Status.conflict, "JSON source changed during decoding", token.start);

    target = allocation.value;
    return Error.init;
}

private Error readOwnedString(T)(ref scope Scanner scanner, ref T target)
{
    TextToken token;
    auto failure = scanner.textValue(token);
    if (failure.code != Status.ok)
        return failure;
    auto buffer = new ubyte[token.length];
    if (!copyText(scanner.bytes, token, buffer))
        return Error(Status.invalidArgument, "invalid JSON string", token.start);

    static if (is(T == immutable(char)[]))
        target = (cast(char[]) buffer).idup;
    else
        target = cast(char[]) buffer;
    return Error.init;
}

private Error readOwnedArray(T)(ref scope Scanner scanner, ref T target, ref scope RequestArena arena,
        ref AllocationPlan plan, uint depth)
{
    if (depth >= scanner.options.maxDepth)
        return Error(Status.resourceExhausted, "JSON depth limit exceeded", scanner.offset);
    if (!scanner.take('['))
        return Error(Status.invalidArgument, "expected a JSON array", scanner.offset);

    alias Element = Unqual!(typeof(T.init[0]));
    Element[] elements;
    scanner.whitespace();
    if (!scanner.take(']'))
    {
        for (;;)
        {
            if (elements.length == scanner.options.maxMembers)
                return Error(Status.resourceExhausted, "JSON array exceeds its element limit", scanner.offset);
            Element value;
            auto failure = readValue!(Element, true)(scanner, value, arena, plan, depth + 1);
            if (failure.code != Status.ok)
                return failure;
            elements ~= value;
            scanner.whitespace();
            if (scanner.take(']'))
                break;
            if (!scanner.take(','))
                return Error(Status.invalidArgument, "expected a JSON array separator", scanner.offset);
        }
    }
    static if (is(typeof(elements) : T))
        target = elements;
    else
        target = elements.idup;
    return Error.init;
}

private Error readArray(T, size_t extent, bool owned)(ref scope Scanner scanner, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, uint depth)
{
    if (depth >= scanner.options.maxDepth || extent > scanner.options.maxMembers)
        return Error(Status.resourceExhausted, "JSON collection limit exceeded", scanner.offset);
    if (!scanner.take('['))
        return Error(Status.invalidArgument, "expected a JSON array", scanner.offset);

    foreach (index; 0 .. extent)
    {
        scanner.whitespace();
        if (index > 0 && !scanner.take(','))
            return Error(Status.invalidArgument, "too few JSON array elements", scanner.offset);
        auto failure = readValue!(typeof(target[index]), owned)(scanner, target[index], arena, plan, depth + 1);
        if (failure.code != Status.ok)
            return failure;
    }
    scanner.whitespace();
    if (!scanner.take(']'))
        return Error(Status.invalidArgument, "too many JSON array elements", scanner.offset);
    return Error.init;
}

private size_t lookup(T)(ref scope Scanner scanner, TextToken token) nothrow @nogc
{
    foreach (index, field; JsonFields!T.entries)
    {
        if (token.hash == field.hash && textEquals(scanner.bytes, token, cast(const(ubyte)[]) field.name))
            return index;
    }
    return noProperty;
}

private Error readObject(T, bool owned)(ref scope Scanner scanner, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, uint depth)
{
    if (depth >= scanner.options.maxDepth)
        return Error(Status.resourceExhausted, "JSON depth limit exceeded", scanner.offset);
    if (!scanner.take('{'))
        return Error(Status.invalidArgument, "expected a JSON object", scanner.offset);

    enum properties = JsonFields!T.entries;
    bool[properties.length] seen;
    KeyScope unknownKeys;
    immutable firstMember = scanner.offset;
    scanner.whitespace();
    uint members;
    if (!scanner.take('}'))
    {
        for (;;)
        {
            auto failure = readObjectMember!(T, owned)(scanner, target, arena, plan, seen,
                    unknownKeys, firstMember, depth + 1, members);
            if (failure.code != Status.ok)
                return failure;
            ++members;
            scanner.whitespace();
            if (scanner.take('}'))
                break;
            if (!scanner.take(','))
                return Error(Status.invalidArgument, "expected a JSON member separator", scanner.offset);
            scanner.whitespace();
        }
    }
    closeKeys(scanner, unknownKeys);
    return readDefaults!(T, owned)(scanner, target, arena, plan, seen, depth + 1);
}

private Error readObjectMember(T, bool owned)(ref scope Scanner scanner, ref T target, ref scope RequestArena arena,
        ref AllocationPlan plan, scope bool[] seen, ref KeyScope unknownKeys, size_t firstMember,
        uint depth, uint members)
{
    if (members >= scanner.options.maxMembers)
        return Error(Status.resourceExhausted, "JSON member limit exceeded", scanner.offset);
    immutable keyOffset = scanner.offset;
    TextToken token;
    auto failure = scanner.text(token);
    if (failure.code != Status.ok)
        return failure;
    immutable index = lookup!T(scanner, token);
    if (scanner.options.rejectDuplicateKeys)
    {
        immutable duplicate = index != noProperty ? seen[index] : repeatedKey(scanner, unknownKeys,
                firstMember, keyOffset, token, depth);
        if (duplicate)
            return Error(Status.invalidArgument, "duplicate JSON member", keyOffset);
    }

    scanner.whitespace();
    if (!scanner.take(':'))
        return Error(Status.invalidArgument, "expected a JSON member colon", scanner.offset);
    if (index == noProperty)
    {
        if (scanner.options.unknownFields == UnknownFields.reject)
            return Error(Status.invalidArgument, "unknown JSON member", keyOffset);
        return skipValue(scanner, depth);
    }
    seen[index] = true;
    return readProperty!(T, owned)(scanner, target, arena, plan, depth, index);
}

private Error readProperty(T, bool owned)(ref scope Scanner scanner, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, uint depth, size_t index)
{
    switch (index)
    {
        static foreach (position, field; JsonFields!T.entries)
        {
    case position:
            static if (field.ignored)
                return skipValue(scanner, depth);
            else
            {
                return readValue!(typeof(mixin("target." ~ field.access)), owned)(scanner,
                        mixin("target." ~ field.access), arena, plan, depth);
            }
        }
    default:
        return Error(Status.invalidArgument, "unknown JSON field descriptor", scanner.offset);
    }
}

private Error readDefaults(T, bool owned)(ref scope Scanner scanner, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, scope const(bool)[] seen, uint depth)
{
    static foreach (position, field; JsonFields!T.entries)
    {
        {
            static if (field.required)
            {
                if (!seen[position])
                    return Error(Status.invalidArgument, "required JSON member is missing", scanner.offset);
            }
            else static if (field.defaultLiteral.length != 0)
            {
                alias Member = typeof(mixin("target." ~ field.access));
                static assert(validDefault!(Member, owned, field.defaultLiteral)(),
                        "invalid JsonDefault for " ~ field.name);
                if (!seen[position])
                {
                    scope fallback = Scanner(cast(const(ubyte)[]) field.defaultLiteral, scanner.options);
                    auto failure = readValue!(Member, owned)(fallback,
                            mixin("target." ~ field.access), arena, plan, depth);
                    if (failure.code != Status.ok)
                        return failure;
                    fallback.whitespace();
                    if (fallback.offset != fallback.bytes.length)
                        return Error(Status.invalidArgument, "invalid JsonDefault literal", scanner.offset);
                }
            }
        }
    }
    return Error.init;
}

/// Validate an annotation's JSON literal at compile time, then bind its typed value.
Error readDefaultValue(T, bool owned, string literal)(ref T target, ref scope RequestArena arena,
        DecodeOptions options, ref AllocationPlan plan)
{
    static assert(validDefault!(T, owned, literal)(), "invalid JSON default literal");
    return readDocument!(T, owned)(cast(const(ubyte)[]) literal, target, arena, options, plan);
}

private bool validDefault(T, bool owned, string literal)()
{
    const options = DecodeOptions.init;
    if (literal.length > options.maxBytes)
        return false;
    RequestArena arena;
    AllocationPlan plan;
    T value;
    return readDocument!(T, owned)(cast(const(ubyte)[]) literal, value, arena, options, plan).code == Status.ok;
}

version (D_BetterC)
{
}
else
{
    /// Encode native strings, dynamic arrays and nested DTOs into independent GC-owned text.
    Result!string writeOwnedJson(T)(scope const ref T value, EncodeOptions options)
    {
        RequestArena none;
        Writer sizing;
        writeValue!(T, true)(sizing, value, none, options, 0);
        if (sizing.error.code != Status.ok)
            return Result!string(null, sizing.error);
        auto data = new ubyte[sizing.length];
        // The output is GC-owned, so the writer need not be scope-limited.
        auto writer = Writer(data);
        writeValue!(T, true)(writer, value, none, options, 0);
        if (writer.error.code != Status.ok)
            return Result!string(null, writer.error);
        return Result!string((cast(const(char)[]) data).idup);
    }
}

/// Generate JSON through the same size and emission passes.
Result!Buffer writeJson(T)(scope const ref T value, ref scope RequestArena arena, EncodeOptions options) nothrow @nogc
{
    return writeArenaBuffer(arena, (ref scope Writer writer) @safe nothrow @nogc {
        writeValue(writer, value, arena, options, 0);
    });
}

private void writeValue(T, bool owned = false)(ref scope Writer writer, scope const ref T value,
        ref scope RequestArena arena, EncodeOptions options, uint depth) nothrow @nogc
{
    alias Value = Unqual!T;
    static if (is(Value == bool))
        writer.append(cast(const(ubyte)[])(value ? "true" : "false"));
    else static if (signedInteger!Value)
        writer.signedNumber(value);
    else static if (unsignedInteger!Value)
        writer.unsignedNumber(value);
    else static if (is(Value == float) || is(Value == double))
        writeDecimal(writer, value);
    else static if (is(Value == enum))
        writeEnum(writer, value);
    else static if (is(Value == char[]) || is(Value == const(char)[]) || is(Value == immutable(char)[]))
        writer.stringValue(cast(const(ubyte)[]) value);
    else static if (is(Value == Text))
        writeHandle(writer, value.bytes, arena);
    else static if (is(Value == Buffer))
        writeHandle(writer, value, arena);
    else static if (is(Value == Element[extent], Element, size_t extent))
        writeArray!(T, owned)(writer, value, arena, options, depth);
    else static if (owned && is(Value == Element[], Element))
        writeArray!(T, owned)(writer, value, arena, options, depth);
    else static if (is(Value == struct))
        writeObject!(T, owned)(writer, value, arena, options, depth);
    else
        static assert(false, "unsupported JSON input type " ~ T.stringof);
}

private void writeEnum(T)(ref scope Writer writer, T value) nothrow @nogc
{
    static foreach (member; __traits(allMembers, T))
    {
        if (value == __traits(getMember, T, member))
        {
            writer.stringValue(cast(const(ubyte)[]) member);
            return;
        }
    }
    writer.fail(Status.invalidArgument, "invalid JSON enum field");
}

private void writeHandle(ref scope Writer writer, Buffer handle, ref scope RequestArena arena) nothrow @nogc
{
    immutable status = arena.read(handle, (scope const(ubyte)[] input) @safe nothrow @nogc {
        writer.stringValue(input);
    });
    if (status != Status.ok)
        writer.fail(status, "stale or foreign JSON string buffer");
}

private bool depthLimit(ref scope Writer writer, EncodeOptions options, uint depth) nothrow @nogc
{
    if (depth < options.maxDepth && depth < 64)
        return false;
    writer.fail(Status.resourceExhausted, "JSON depth limit exceeded");
    return true;
}

private void writeArray(T, bool owned)(ref scope Writer writer, scope const ref T value,
        ref scope RequestArena arena, EncodeOptions options, uint depth) nothrow @nogc
{
    if (depthLimit(writer, options, depth))
        return;
    if (value.length > DecodeOptions.init.maxMembers)
    {
        writer.fail(Status.resourceExhausted, "JSON array exceeds its element limit");
        return;
    }
    writer.put('[');
    foreach (index, ref element; value)
    {
        if (index != 0)
            writer.put(',');
        writeValue!(typeof(element), owned)(writer, element, arena, options, depth + 1);
    }
    writer.put(']');
}

private void writeObject(T, bool owned)(ref scope Writer writer, scope const ref T value,
        ref scope RequestArena arena, EncodeOptions options, uint depth) nothrow @nogc
{
    if (depthLimit(writer, options, depth))
        return;
    writer.put('{');
    bool first = true;
    static immutable canonical = JsonFields!(Unqual!T).sorted;
    foreach (index; 0 .. JsonFields!(Unqual!T).entries.length)
    {
        const position = options.canonical ? canonical[index] : index;
        writeProperty!(T, owned)(writer, value, arena, options, depth + 1, position, first);
    }
    writer.put('}');
}

private void writeProperty(T, bool owned)(ref scope Writer writer, scope const ref T value,
        ref scope RequestArena arena, EncodeOptions options, uint depth, size_t index, ref bool first) nothrow @nogc
{
    switch (index)
    {
        static foreach (position, field; JsonFields!(Unqual!T).entries)
        {
    case position:
            static if (field.ignored)
            {
                if (options.omitIgnored)
                    return;
                // Intentionally ignored members may be application-only types.
                static if (!__traits(compiles, writeValue!(typeof(mixin("value." ~ field.access)),
                        owned)(writer, mixin("value." ~ field.access), arena, options, depth)))
                {
                    writer.fail(Status.invalidArgument, "ignored JSON member has no serializable type");
                    return;
                }
                else
                    writeNamedValue!(typeof(mixin("value." ~ field.access)), owned)(writer,
                            mixin("value." ~ field.access), arena, options, depth, field.name, first);
            }
            else
                writeNamedValue!(typeof(mixin("value." ~ field.access)), owned)(writer,
                        mixin("value." ~ field.access), arena, options, depth, field.name, first);
            return;
        }
    default:
        writer.fail(Status.invalidArgument, "unknown JSON field descriptor");
        return;
    }
}

private void writeNamedValue(T, bool owned)(ref scope Writer writer, scope const ref T value,
        ref scope RequestArena arena, EncodeOptions options, uint depth, string name, ref bool first) nothrow @nogc
{
    if (!first)
        writer.put(',');
    first = false;
    writer.stringValue(cast(const(ubyte)[]) name);
    writer.put(':');
    writeValue!(T, owned)(writer, value, arena, options, depth);
}
