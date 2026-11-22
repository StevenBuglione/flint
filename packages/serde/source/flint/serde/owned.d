/// Native startup and worker JSON adapter with explicit GC-owned output.
module flint.serde.owned;

import flint.arena : Result;
import flint.serde.internal.types : DecodeOptions;
public import flint.serde.internal.toml_entries : TomlEntry;

@safe:

version (D_BetterC)
{
}
else
{
    /// Decode strings and dynamic arrays into independent native storage.
    Result!T deserialize(T)(scope const(char)[] input, DecodeOptions options = DecodeOptions.init)
    {
        import flint.serde.internal.json_codec : readOwnedJson;

        Result!T result;
        result.error = readOwnedJson(cast(const(ubyte)[]) input, result.value, options);
        return result;
    }

    /// Decode a TOML document into independent native strings and arrays.
    Result!T deserializeToml(T)(scope const(char)[] input, DecodeOptions options = DecodeOptions.init)
    {
        import flint.serde.internal.toml_codec : readOwnedToml;

        Result!T result;
        result.error = readOwnedToml(cast(const(ubyte)[]) input, result.value, options);
        return result;
    }

    /// Read normalized TOML assignments and their original key positions.
    Result!(TomlEntry[]) readTomlEntries(scope const(char)[] input, DecodeOptions options = DecodeOptions.init)
    {
        import flint.serde.internal.toml_entries : collectEntries;

        return collectEntries(cast(const(ubyte)[]) input, options);
    }
}
