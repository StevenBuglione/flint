/// Bounded serialization between typed values and caller-owned arena buffers.
module flint.serde;

import flint.arena : Buffer, Error, RequestArena, Result;
public import flint.serde.internal.types : DecodeOptions, EncodeOptions, JsonDefault, JsonFlatten,
    JsonIgnore, JsonName, JsonRequired, TomlDate, TomlDateTime, TomlTime, UnknownFields;

@safe:

/// Decode a complete UTF-8 JSON document and commit only on success.
Error decodeInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc
{
    import flint.serde.internal.json_codec : readJson;

    return readJson(input, destination, arena, options);
}

/// Encode one value as compact UTF-8 JSON in the supplied arena.
Result!Buffer encodeJson(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc
{
    import flint.serde.internal.json_codec : writeJson;

    return writeJson(value, arena, options);
}

/// Generate the deterministic supported JSON Schema subset for a DTO.
Result!Buffer jsonSchema(T)(ref scope RequestArena arena) nothrow @nogc
{
    import flint.serde.internal.schema : writeSchema;

    return writeSchema!T(arena);
}

/// Decode a complete TOML document into a typed arena-backed value.
Error decodeTomlInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc
{
    import flint.serde.internal.toml_codec : readToml;

    return readToml(input, destination, arena, options);
}

/// Encode a typed value as a TOML document.
Result!Buffer encodeToml(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc
{
    import flint.serde.internal.toml_codec : writeToml;

    return writeToml(value, arena, options);
}
