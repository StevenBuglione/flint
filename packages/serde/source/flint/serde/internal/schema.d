/// Deterministic schema output for the subset implemented by the typed codecs.
module flint.serde.internal.schema;

import flint.arena : Buffer, RequestArena, Result, Status, Text;
import flint.serde.internal.fields : JsonFields;
import flint.serde.internal.writer : Writer, writeArenaBuffer;
import std.traits : Unqual;

@safe:

/// Render the requested type's schema using the same field names as the JSON binder.
Result!Buffer writeSchema(T)(ref scope RequestArena arena) nothrow @nogc
{
    return writeArenaBuffer(arena, (ref scope Writer writer) @safe nothrow @nogc {
        typeSchema!T(writer, 0);
    });
}

private void typeSchema(T)(ref scope Writer writer, uint depth) nothrow @nogc
{
    alias Value = Unqual!T;
    static if (is(Value == bool))
        writer.append(cast(const(ubyte)[]) `{"type":"boolean"}`);
    else static if (is(Value == float) || is(Value == double))
        writer.append(cast(const(ubyte)[]) `{"type":"number"}`);
    else static if (is(Value == Text) || is(Value == Buffer) || is(Value == char[])
            || is(Value == const(char)[]) || is(Value == immutable(char)[]))
        writer.append(cast(const(ubyte)[]) `{"type":"string"}`);
    else static if (is(Value == enum))
        enumSchema!Value(writer);
    else static if (is(Value == byte) || is(Value == short) || is(Value == int) || is(Value == long)
            || is(Value == ubyte) || is(Value == ushort) || is(Value == uint) || is(Value == ulong))
        integerSchema!Value(writer);
    else static if (is(Value == Element[extent], Element, size_t extent) || is(Value == Element[], Element))
    {
        if (depth >= 64)
        {
            writer.fail(Status.resourceExhausted, "JSON Schema depth limit exceeded");
            return;
        }
        writer.append(cast(const(ubyte)[]) `{"type":"array","items":`);
        typeSchema!Element(writer, depth + 1);
        writer.put('}');
    }
    else static if (is(Value == struct))
        objectSchema!Value(writer, depth);
    else
        static assert(false, "unsupported JSON Schema type " ~ T.stringof);
}

private void enumSchema(T)(ref scope Writer writer) nothrow @nogc
{
    writer.append(cast(const(ubyte)[]) `{"type":"string","enum":[`);
    static foreach (index, member; __traits(allMembers, T))
    {
        static if (index != 0)
            writer.put(',');
        writer.stringValue(cast(const(ubyte)[]) member);
    }
    writer.append(cast(const(ubyte)[]) "]}");
}

private void integerSchema(T)(ref scope Writer writer) nothrow @nogc
{
    writer.append(cast(const(ubyte)[]) `{"type":"integer","minimum":`);
    writer.signedNumber(T.min);
    writer.append(cast(const(ubyte)[]) `,"maximum":`);
    writer.unsignedNumber(T.max);
    writer.put('}');
}

private void objectSchema(T)(ref scope Writer writer, uint depth) nothrow @nogc
{
    if (depth >= 64)
    {
        writer.fail(Status.resourceExhausted, "JSON Schema depth limit exceeded");
        return;
    }
    enum descriptors = JsonFields!T.entries;
    enum positions = JsonFields!T.sorted;
    writer.append(cast(const(ubyte)[]) `{"type":"object","properties":{`);
    bool first = true;
    static foreach (position; positions)
    {
        {
            enum field = descriptors[position];
            static if (!field.ignored)
            {
                if (!first)
                    writer.put(',');
                first = false;
                writer.stringValue(cast(const(ubyte)[]) field.name);
                writer.put(':');
                typeSchema!(typeof(mixin("T.init." ~ field.access)))(writer, depth + 1);
            }
        }
    }
    writer.append(cast(const(ubyte)[]) `},"required":[`);
    first = true;
    static foreach (position; positions)
    {
        {
            enum field = descriptors[position];
            static if (field.required)
            {
                if (!first)
                    writer.put(',');
                first = false;
                writer.stringValue(cast(const(ubyte)[]) field.name);
            }
        }
    }
    writer.append(cast(const(ubyte)[]) `],"additionalProperties":false}`);
}
