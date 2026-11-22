/// Typed binding and compact TOML emission using Serde field descriptors.
module flint.serde.internal.toml_codec;

import flint.arena : Buffer, Error, RequestArena, Result, Status, Text;
import flint.serde.internal.decimal : writeDecimal;
import flint.serde.internal.fields : JsonFields;
import flint.serde.internal.json_codec : AllocationPlan, bounded, readDefaultValue;
import flint.serde.internal.toml_document : Document, Node, NodeKind, rootNode;
import flint.serde.internal.toml_text : bare, emitText, keyEquals;
import flint.serde.internal.toml_values : ScalarKind, booleanValue, dateValue, datetimeValue,
    emitDate, emitDatetime, emitTime, floatingValue, integerValue, timeValue;
import flint.serde.internal.types : DecodeOptions, EncodeOptions, TomlDate, TomlDateTime, TomlTime, UnknownFields;
import flint.serde.internal.writer : Writer, writeArenaBuffer;
import std.traits : Unqual;

@safe:

private enum signedInteger(T) = is(T == byte) || is(T == short) || is(T == int) || is(T == long);
private enum unsignedInteger(T) = is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong);
private enum characterArray(T) = is(T == char[]) || is(T == const(char)[]) || is(T == immutable(char)[]);
private alias Arena = RequestArena;
private enum noField = size_t.max;

/// Parse into a temporary DTO and commit only once all needed arena bytes fit.
Error readToml(T)(scope const(ubyte)[] input, ref T target, ref scope Arena arena, DecodeOptions options) nothrow @nogc
{
    static assert(is(T == struct), "TOML documents require a struct root type");
    options = bounded(options);
    if (input.length > options.maxBytes)
        return Error(Status.resourceExhausted, "TOML document exceeds its byte limit", options.maxBytes);

    scope document = Document(input, options);
    auto failure = document.parse();
    if (failure.code != Status.ok)
        return failure;

    AllocationPlan plan;
    T temporary;
    failure = bindTable!(T, false)(document, rootNode, temporary, arena, plan);
    if (failure.code != Status.ok)
        return failure;

    if (plan.storesBytes)
    {
        const usage = arena.stats();
        if (plan.bytes > usage.capacity - usage.used)
            return Error(Status.outOfMemory, "arena capacity exhausted");

        plan.materialize = true;
        failure = bindTable!(T, false)(document, rootNode, temporary, arena, plan);
        if (failure.code != Status.ok)
            return failure;
    }

    target = temporary;
    return Error.init;
}

/// Bind the same document into independent GC-owned storage at startup.
Error readOwnedToml(T)(scope const(ubyte)[] input, ref T destination, DecodeOptions options)
{
    static assert(is(T == struct), "TOML documents require a struct root type");
    options = bounded(options);
    if (input.length > options.maxBytes)
        return Error(Status.resourceExhausted, "TOML document exceeds its byte limit", options.maxBytes);
    scope document = Document(input, options);
    auto failure = document.parse();
    if (failure.code != Status.ok)
        return failure;

    RequestArena unusedArena;
    AllocationPlan plan;
    T temporary;
    failure = bindTable!(T, true)(document, rootNode, temporary, unusedArena, plan);
    if (failure.code == Status.ok)
        destination = temporary;
    return failure;
}

private Error bindingError(Node entry, string description) nothrow @nogc
{
    return Error(Status.invalidArgument, description, entry.kind == NodeKind.scalar
            ? entry.token.first : entry.key.first);
}

private bool tableKind(NodeKind kind) nothrow @nogc
{
    return kind == NodeKind.implicitTable || kind == NodeKind.namedTable
        || kind == NodeKind.dottedTable || kind == NodeKind.inlineTable || kind == NodeKind.tableElement;
}

private Error bindTable(T, bool owned)(ref scope const Document document, ushort index, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan)
{
    const entry = document.node(index);
    if (!tableKind(entry.kind))
        return bindingError(entry, "expected a TOML table");

    enum count = JsonFields!T.entries.length;
    bool[count] seen;

    ushort child = entry.first;
    while (child != 0)
    {
        const member = document.node(child);
        const position = fieldIndex!T(document.input[member.key.first .. member.key.last]);
        if (position == noField)
        {
            if (document.options.unknownFields == UnknownFields.reject)
                return Error(Status.invalidArgument, "unknown TOML key", member.key.first);
        }
        else
        {
            seen[position] = true;
            auto failure = bindMember!(T, owned)(document, child, target, arena, plan, position);
            if (failure.code != Status.ok)
                return failure;
        }
        child = member.next;
    }
    return bindMissing!(T, owned)(document, entry, target, arena, plan, seen);
}

private size_t fieldIndex(T)(scope const(ubyte)[] token) nothrow @nogc
{
    static immutable fields = JsonFields!T.entries;
    foreach (index, ref const field; fields)
    {
        if (keyEquals(token, cast(const(ubyte)[]) field.name))
            return index;
    }
    return noField;
}

private Error bindMember(T, bool owned)(ref scope const Document document, ushort index, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, size_t position)
{
    switch (position)
    {
        static foreach (property, field; JsonFields!T.entries)
        {
    case property:
            static if (field.ignored)
                return Error.init;
            else
            {
                return bindValue!(typeof(mixin("target." ~ field.access)), owned)(document, index,
                        mixin("target." ~ field.access), arena, plan);
            }
        }
    default:
        return bindingError(document.node(index), "unknown TOML field descriptor");
    }
}

private Error bindMissing(T, bool owned)(ref scope const Document document, Node entry, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan, scope const(bool)[] seen)
{
    static foreach (property, field; JsonFields!T.entries)
    {
        {
            static if (field.required)
            {
                if (!seen[property])
                    return bindingError(entry, "required TOML key is missing");
            }
            else static if (field.defaultLiteral.length != 0)
            {
                if (!seen[property])
                {
                    alias Member = typeof(mixin("target." ~ field.access));
                    auto failure = readDefaultValue!(Member, owned, field.defaultLiteral)(
                            mixin("target." ~ field.access), arena, document.options, plan);
                    if (failure.code != Status.ok)
                        return failure;
                }
            }
        }
    }
    return Error.init;
}

private Error bindValue(T, bool owned)(ref scope const Document document, ushort index, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan)
{
    const entry = document.node(index);
    scope token = document.input[entry.token.first .. entry.token.last];
    static if (is(T == bool))
        return bindBoolean(entry, token, target);
    else static if (signedInteger!T || unsignedInteger!T)
        return bindInteger(entry, token, target);
    else static if (is(T == float) || is(T == double))
        return bindFloat(entry, token, target);
    else static if (is(T == TomlDate) || is(T == TomlTime) || is(T == TomlDateTime))
        return bindCalendar(entry, token, target);
    else static if (is(T == enum))
        return bindEnum(entry, token, target);
    else static if (is(T == Text) || is(T == Buffer))
    {
        static assert(!owned, "native owned DTOs cannot retain arena handles");
        return bindHandle(entry, token, target, arena, plan);
    }
    else static if (owned && characterArray!T)
        return bindOwnedText(entry, token, target);
    else static if (owned && is(T == Element[], Element))
        return bindOwnedArray(document, entry, target, arena, plan);
    else static if (is(T == Element[extent], Element, size_t extent))
        return bindFixedArray!(T, extent, owned)(document, entry, target, arena, plan);
    else static if (is(T == struct))
        return bindTable!(T, owned)(document, index, target, arena, plan);
    else
        static assert(false, "unsupported TOML output type " ~ T.stringof);
    return Error.init;
}

private Error bindCalendar(T)(Node entry, scope const(ubyte)[] token, ref T target) nothrow @nogc
{
    static if (is(T == TomlDate))
        const accepted = entry.scalar == ScalarKind.date && dateValue(token, target);
    else static if (is(T == TomlTime))
        const accepted = entry.scalar == ScalarKind.time && timeValue(token, target);
    else
        const accepted = entry.scalar == ScalarKind.datetime && datetimeValue(token, target);
    return accepted ? Error.init : bindingError(entry, "TOML calendar value has the wrong type");
}

private Error bindBoolean(Node entry, scope const(ubyte)[] token, ref bool target) nothrow @nogc
{
    if (entry.scalar != ScalarKind.boolean)
        return bindingError(entry, "expected a TOML boolean");
    target = booleanValue(token);
    return Error.init;
}

private Error bindHandle(T)(Node entry, scope const(ubyte)[] token, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan) nothrow @nogc
{
    Buffer buffer;
    auto failure = bindArenaText(entry, token, buffer, arena, plan);
    if (failure.code != Status.ok)
        return failure;
    static if (is(T == Text))
        target = Text(buffer);
    else
        target = buffer;
    return Error.init;
}

private Error bindInteger(T)(Node entry, scope const(ubyte)[] token, ref T target) nothrow @nogc
{
    long[1] parsed;
    if (entry.scalar != ScalarKind.integer || !integerValue(token, parsed[0]))
        return bindingError(entry, "expected a TOML integer");
    const value = parsed[0];
    static if (signedInteger!T)
    {
        if (value < T.min || value > T.max)
            return bindingError(entry, "TOML integer is outside its field range");
    }
    else
    {
        if (value < 0 || cast(ulong) value > T.max)
            return bindingError(entry, "TOML integer is outside its field range");
    }
    target = cast(T) value;
    return Error.init;
}

private Error bindFloat(T)(Node entry, scope const(ubyte)[] token, ref T target) nothrow @nogc
{
    if (entry.scalar == ScalarKind.integer)
    {
        long[1] parsed;
        if (integerValue(token, parsed[0]))
        {
            target = cast(T) parsed[0];
            return Error.init;
        }
    }
    else if (entry.scalar == ScalarKind.fraction && floatingValue(token, target))
        return Error.init;
    return bindingError(entry, "TOML value is outside its floating point type");
}

private Error bindEnum(T)(Node entry, scope const(ubyte)[] token, ref T target) nothrow @nogc
{
    if (entry.scalar != ScalarKind.text)
        return bindingError(entry, "expected a TOML enum string");
    static foreach (member; __traits(allMembers, T))
    {
        if (keyEquals(token, cast(const(ubyte)[]) member, true))
        {
            target = __traits(getMember, T, member);
            return Error.init;
        }
    }
    return bindingError(entry, "unknown TOML enum value");
}

private Error bindFixedArray(T, size_t extent, bool owned)(ref scope const Document document,
        Node entry, ref T target, ref scope RequestArena arena, ref AllocationPlan plan)
{
    if ((entry.kind != NodeKind.array && entry.kind != NodeKind.tableArray) || entry.count != extent)
        return bindingError(entry, "TOML array has a different extent");

    ushort child = entry.first;
    foreach_reverse (index; 0 .. extent)
    {
        auto failure = bindValue!(typeof(target[index]), owned)(document, child, target[index], arena, plan);
        if (failure.code != Status.ok)
            return failure;
        child = document.node(child).next;
    }
    return Error.init;
}

private Error bindOwnedArray(T)(ref scope const Document document, Node entry, ref T target,
        ref scope RequestArena arena, ref AllocationPlan plan)
{
    if (entry.kind != NodeKind.array && entry.kind != NodeKind.tableArray)
        return bindingError(entry, "expected a TOML array");

    alias Element = Unqual!(typeof(T.init[0]));
    auto values = new Element[entry.count];
    ushort child = entry.first;
    foreach_reverse (index; 0 .. values.length)
    {
        auto failure = bindValue!(Element, true)(document, child, values[index], arena, plan);
        if (failure.code != Status.ok)
            return failure;
        child = document.node(child).next;
    }
    static if (is(typeof(values) : T))
        target = values;
    else
        target = values.idup;
    return Error.init;
}

private Error bindArenaText(Node entry, scope const(ubyte)[] token, ref Buffer target,
        ref scope RequestArena arena, ref AllocationPlan plan) nothrow @nogc
{
    if (entry.scalar != ScalarKind.text)
        return bindingError(entry, "expected a TOML string");

    Writer sizing;
    emitText(sizing, token);
    if (sizing.error.code != Status.ok)
        return bindingError(entry, "invalid TOML string");
    if (!plan.materialize)
    {
        if (sizing.length > size_t.max - plan.bytes)
            return Error(Status.resourceExhausted, "decoded TOML byte count overflows", entry.token.first);
        plan.bytes += sizing.length;
        plan.storesBytes = true;
        return Error.init;
    }

    auto allocation = arena.allocate(sizing.length, 1);
    if (!allocation.ok())
        return allocation.error;
    Status emission;
    const status = arena.write(allocation.value, (scope ubyte[] output) @safe nothrow @nogc {
        scope writer = Writer(output);
        emitText(writer, token);
        emission = writer.error.code;
    });
    if (status != Status.ok || emission != Status.ok)
        return bindingError(entry, "TOML source changed during decoding");

    target = allocation.value;
    return Error.init;
}

private Error bindOwnedText(T)(Node entry, scope const(ubyte)[] token, ref T target)
{
    if (entry.scalar != ScalarKind.text)
        return bindingError(entry, "expected a TOML string");
    Writer sizing;
    emitText(sizing, token);
    if (sizing.error.code != Status.ok)
        return bindingError(entry, "invalid TOML string");

    auto decoded = new ubyte[sizing.length];
    scope writer = Writer(decoded);
    emitText(writer, token);
    if (writer.error.code != Status.ok)
        return bindingError(entry, "TOML source changed during decoding");
    static if (is(T == immutable(char)[]))
        target = (cast(char[]) decoded).idup;
    else
        target = cast(char[]) decoded;
    return Error.init;
}

/// Render a TOML document with a bounded writer, using inline nested tables.
Result!Buffer writeToml(T)(scope const ref T input, ref scope RequestArena arena, EncodeOptions options) nothrow @nogc
{
    static assert(is(Unqual!T == struct), "TOML documents require a struct root type");
    return writeArenaBuffer(arena, (ref scope Writer writer) @safe nothrow @nogc {
        emitTable(writer, input, arena, options, 0, false);
    });
}

private void emitTable(T)(ref scope Writer writer, scope const ref T input, ref scope RequestArena arena,
        EncodeOptions options, uint depth, bool inlineValue) nothrow @nogc
{
    if (depth >= options.maxDepth || depth >= 64)
    {
        writer.fail(Status.resourceExhausted, "TOML depth limit exceeded");
        return;
    }

    if (inlineValue)
        writer.put('{');
    bool first = true;
    static immutable canonical = JsonFields!(Unqual!T).sorted;
    foreach (index; 0 .. canonical.length)
    {
        const property = options.canonical ? canonical[index] : index;
        emitMember(writer, input, arena, options, depth + 1, inlineValue, property, first);
    }
    if (inlineValue)
        writer.put('}');
}

private void emitMember(T)(ref scope Writer writer, scope const ref T input, ref scope RequestArena arena,
        EncodeOptions options, uint depth, bool inlineValue, size_t property, ref bool first) nothrow @nogc
{
    switch (property)
    {
        static foreach (position, field; JsonFields!(Unqual!T).entries)
        {
    case position:
            static if (field.ignored)
            {
                if (options.omitIgnored)
                    return;
            }
            static if (field.ignored && !__traits(compiles, emitValue(writer,
                    mixin("input." ~ field.access), arena, options, depth)))
                writer.fail(Status.invalidArgument, "ignored TOML member has no serializable type");
            else
                emitNamedValue(writer, mixin("input." ~ field.access), arena, options, depth,
                        inlineValue, field.name, first);
            return;
        }
    default:
        writer.fail(Status.invalidArgument, "unknown TOML field descriptor");
        return;
    }
}

private void emitNamedValue(T)(ref scope Writer writer, scope const ref T input, ref scope RequestArena arena,
        EncodeOptions options, uint depth, bool inlineValue, string name, ref bool first) nothrow @nogc
{
    if (inlineValue && !first)
        writer.append(cast(const(ubyte)[]) ", ");
    first = false;
    emitKey(writer, cast(const(ubyte)[]) name);
    writer.append(cast(const(ubyte)[]) " = ");
    emitValue(writer, input, arena, options, depth);
    if (!inlineValue)
        writer.put('\n');
}

private void emitKey(ref scope Writer writer, scope const(ubyte)[] key) nothrow @nogc
{
    if (key.length == 0)
    {
        writer.stringValue(key, true);
        return;
    }
    foreach (byteValue; key)
    {
        if (!bare(byteValue))
        {
            writer.stringValue(key, true);
            return;
        }
    }
    writer.append(key);
}

private void emitValue(T)(ref scope Writer writer, scope const ref T input, ref scope RequestArena arena,
        EncodeOptions options, uint depth) nothrow @nogc
{
    alias Value = Unqual!T;
    static if (is(Value == bool))
        writer.append(cast(const(ubyte)[])(input ? "true" : "false"));
    else static if (signedInteger!Value)
        writer.signedNumber(input);
    else static if (unsignedInteger!Value)
    {
        if (input > long.max)
            writer.fail(Status.invalidArgument, "TOML integer exceeds the signed 64-bit range");
        else
            writer.unsignedNumber(input);
    }
    else static if (is(Value == float) || is(Value == double))
        writeDecimal(writer, input, true);
    else static if (is(Value == TomlDate))
        emitDate(writer, input);
    else static if (is(Value == TomlTime))
        emitTime(writer, input);
    else static if (is(Value == TomlDateTime))
        emitDatetime(writer, input);
    else static if (is(Value == enum))
        emitEnum(writer, input);
    else static if (characterArray!Value)
        writer.stringValue(cast(const(ubyte)[]) input, true);
    else static if (is(Value == Text))
        emitHandle(writer, input.bytes, arena);
    else static if (is(Value == Buffer))
        emitHandle(writer, input, arena);
    else static if (is(Value == Element[extent], Element, size_t extent))
        emitArray(writer, input, arena, options, depth);
    else static if (is(Value == struct))
        emitTable(writer, input, arena, options, depth, true);
    else
        static assert(false, "unsupported TOML input type " ~ T.stringof);
}

private void emitEnum(T)(ref scope Writer writer, T value) nothrow @nogc
{
    static foreach (member; __traits(allMembers, T))
    {
        if (value == __traits(getMember, T, member))
        {
            writer.stringValue(cast(const(ubyte)[]) member, true);
            return;
        }
    }
    writer.fail(Status.invalidArgument, "invalid TOML enum field");
}

private void emitHandle(ref scope Writer writer, Buffer input, ref scope RequestArena arena) nothrow @nogc
{
    const status = arena.read(input, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        writer.stringValue(bytes, true);
    });
    if (status != Status.ok)
        writer.fail(status, "stale or foreign TOML string buffer");
}

private void emitArray(T)(ref scope Writer writer, scope const ref T input, ref scope RequestArena arena,
        EncodeOptions options, uint depth) nothrow @nogc
{
    if (depth >= 64 || depth >= options.maxDepth || input.length > DecodeOptions.init.maxMembers)
    {
        writer.fail(Status.resourceExhausted, "TOML array exceeds its bounds");
        return;
    }

    writer.put('[');
    foreach (index, ref item; input)
    {
        if (index > 0)
            writer.append(cast(const(ubyte)[]) ", ");
        emitValue(writer, item, arena, options, depth + 1);
    }
    writer.put(']');
}
