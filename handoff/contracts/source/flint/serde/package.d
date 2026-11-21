/// Public API contract; declarations are not runtime implementations.
module flint.serde;
import flint.arena : Error, Result, Buffer, Text, RequestArena;

@safe:
struct JsonName
{
    string value;
}

struct JsonIgnore
{
}

struct JsonDefault
{
    string value;
}

struct JsonRequired
{
}

struct JsonFlatten
{
}

struct TomlDate
{
    ushort year;
    ubyte month;
    ubyte day;
}

struct TomlTime
{
    ubyte hour;
    ubyte minute;
    ubyte second;
    uint nanosecond;
}

struct TomlDateTime
{
    TomlDate date;
    TomlTime time;
    short offsetMinutes;
    bool hasOffset;
}

enum UnknownFields
{
    reject,
    ignore
}

struct DecodeOptions
{
    uint maxDepth = 64;
    uint maxMembers = 1024;
    size_t maxBytes = 1048576;
    UnknownFields unknownFields = UnknownFields.reject;
    bool rejectDuplicateKeys = true;
}

struct EncodeOptions
{
    bool canonical = false;
    bool omitIgnored = true;
    uint maxDepth = 64;
}

Error decodeInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc;
Result!Buffer encodeJson(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc;
Error decodeTomlInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc;
Result!Buffer encodeToml(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc;
Result!Buffer jsonSchema(T)(ref scope RequestArena arena) nothrow @nogc;
