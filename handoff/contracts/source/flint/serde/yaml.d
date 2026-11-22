/// Optional libyaml adapter contract; requires the pinned C archive.
module flint.serde.yaml;
import flint.arena : Error, Result, Buffer, RequestArena;
import flint.serde : DecodeOptions, EncodeOptions;

@safe:
Error decodeYamlInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc;
Result!Buffer encodeYaml(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc;
