/// Compile-time field descriptors for the explicitly supplied DTO.
module flint.serde.internal.fields;

import flint.serde.internal.json_scan : nameHashSeed, advanceNameHash, readUtf8;
import flint.serde.internal.types : JsonDefault, JsonFlatten, JsonIgnore, JsonName, JsonRequired;

@safe:

/// Serialization policy of a single field.
struct Field
{
    /// Decoded property name.
    string name;
    /// Member path relative to the destination DTO.
    string access;
    /// JSON default literal, or empty when no default was supplied.
    string defaultLiteral;
    /// Whether a missing property fails decoding.
    bool required;
    /// Whether this field is ignored by default.
    bool ignored;
    /// Decoded Unicode hash used by the field lookup.
    uint hash;
}

private struct Annotations
{
    string name;
    string fallback;
    uint names;
    uint defaults;
    uint required;
    uint ignored;
    uint flattened;
}

private Annotations annotations(T, size_t index)()
{
    Annotations info;
    info.name = __traits(identifier, T.tupleof[index]);
    static foreach (attribute; __traits(getAttributes, T.tupleof[index]))
    {
        static if (is(typeof(attribute) == JsonName))
        {
            info.name = attribute.value;
            ++info.names;
        }
        else static if (is(typeof(attribute) == JsonDefault))
        {
            info.fallback = attribute.value;
            ++info.defaults;
        }
        else static if (is(attribute == JsonRequired) || is(typeof(attribute) == JsonRequired))
            ++info.required;
        else static if (is(attribute == JsonIgnore) || is(typeof(attribute) == JsonIgnore))
            ++info.ignored;
        else static if (is(attribute == JsonFlatten) || is(typeof(attribute) == JsonFlatten))
            ++info.flattened;
    }
    return info;
}

private struct Hash
{
    uint value;
    bool valid;
}

private Hash nameHash()(scope const(ubyte)[] name) nothrow @nogc
{
    uint hash = nameHashSeed;
    size_t offset;
    while (offset < name.length)
    {
        const point = readUtf8(name, offset);
        if (!point.valid)
            return Hash.init;
        hash = advanceNameHash(hash, point.scalar);
    }
    return Hash(hash, true);
}

private Field[] describe(T)(string base, size_t depth)
{
    assert(depth <= 64, "JsonFlatten exceeds the serializer nesting bound");

    Field[] result;
    static foreach (index, member; T.tupleof)
    {
        {
            enum info = annotations!(T, index)();
            enum name = __traits(identifier, T.tupleof[index]);
            static assert(info.names <= 1 && info.defaults <= 1 && info.required <= 1
                    && info.ignored <= 1 && info.flattened <= 1, "repeated JSON attribute on " ~ name);
            static assert(!(info.required && info.defaults), "JsonRequired conflicts with JsonDefault on " ~ name);
            static assert(!info.defaults || info.fallback.length != 0, "empty JsonDefault on " ~ name);
            static assert(!info.ignored || (info.names == 0 && info.defaults == 0
                    && info.required == 0 && info.flattened == 0),
                    "JsonIgnore conflicts with JSON attributes on " ~ name);
            static assert(!info.flattened || (info.names == 0 && info.defaults == 0
                    && info.required == 0), "JsonFlatten conflicts with JSON attributes on " ~ name);

            static if (info.flattened)
            {
                alias Nested = typeof(member);
                static assert(is(Nested == struct), "JsonFlatten requires a struct field: " ~ name);
                result ~= describe!Nested(base ~ name ~ ".", depth + 1);
            }
            else
            {
                enum hash = nameHash(cast(const(ubyte)[]) info.name);
                static assert(hash.valid, "invalid UTF-8 in JsonName on " ~ name);
                result ~= Field(info.name, base ~ name, info.fallback, info.required != 0,
                        info.ignored != 0, hash.value);
            }
        }
    }
    return result;
}

private bool before()(string left, string right) pure nothrow @nogc
{
    foreach (index, byteValue; left)
    {
        if (index == right.length)
            return false;
        if (byteValue != right[index])
            return byteValue < right[index];
    }
    return left.length < right.length;
}

private size_t[] canonicalOrder()(scope const(Field)[] fields)
{
    auto order = new size_t[fields.length];
    foreach (index; 0 .. order.length)
    {
        size_t position = index;
        while (position > 0 && before(fields[index].name, fields[order[position - 1]].name))
        {
            order[position] = order[position - 1];
            --position;
        }
        order[position] = index;
    }
    foreach (index; 1 .. order.length)
    {
        assert(fields[order[index - 1]].name != fields[order[index]].name,
                "duplicate serialized field name: " ~ fields[order[index]].name);
    }
    return order;
}

/// Precomputed lookup and canonical order shared by the typed codecs.
template JsonFields(T)
{
    enum entries = describe!T("", 0);
    static assert(entries.length <= 128, "Flint DTOs support at most 128 serialized fields");
    enum sorted = canonicalOrder(entries);
    static assert(sorted.length == entries.length);
}
