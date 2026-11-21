/// Opt-in YAML data conversion through the checksum-pinned libyaml provider.
module flint.serde.yaml;

import flint.arena : Buffer, Error, RequestArena, Result, Status;
import flint.serde.internal.types : DecodeOptions, EncodeOptions;

@safe:

version (FlintNativeLibyaml)
{
    import flint.serde.internal.yaml_codec : readYaml;
    import flint.serde.internal.json_codec : writeJson;
}

/// Decode one YAML document with bounded size, nesting and members.
Error decodeYamlInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc
{
    version (FlintNativeLibyaml)
        return readYaml(input, destination, arena, options);
    else
        return Error(Status.unsupported, "YAML requires the pinned libyaml provider");
}

/// Emit the JSON-compatible YAML flow form, with no implicit type conversions.
Result!Buffer encodeYaml(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc
{
    version (FlintNativeLibyaml)
        return writeJson(value, arena, options);
    else
        return Result!Buffer(Buffer.init, Error(Status.unsupported, "YAML requires the pinned libyaml provider"));
}
