/// Shared field annotations and bounded serialization configuration.
module flint.serde.internal.types;

@safe:
/// Replace the field's JSON property name.
struct JsonName
{
    /// Annotation argument.
    string value;
}

/// Exclude a field from decoding and default encoding.
struct JsonIgnore
{
}

/// Parse this JSON literal when the field is absent.
struct JsonDefault
{
    /// Annotation argument.
    string value;
}

/// Require the input to contain this field.
struct JsonRequired
{
}

/// Include a nested DTO's fields in the containing object.
struct JsonFlatten
{
}

/// A TOML local calendar date.
struct TomlDate
{
    /// Four-digit year.
    ushort year;
    /// Month from 1 to 12.
    ubyte month;
    /// Day within the month.
    ubyte day;
}

/// A TOML local clock time.
struct TomlTime
{
    /// Hour from 0 to 23.
    ubyte hour;
    /// Minute from 0 to 59.
    ubyte minute;
    /// Second from 0 to 59.
    ubyte second;
    /// Fractional second in nanoseconds.
    uint nanosecond;
}

/// A TOML date and time with an optional numeric offset.
struct TomlDateTime
{
    /// Calendar date.
    TomlDate date;
    /// Local clock reading.
    TomlTime time;
    /// Signed offset east of UTC in minutes.
    short offsetMinutes;
    /// Whether this date and time includes a UTC offset.
    bool hasOffset;
}

/// Action for object members absent from the DTO.
enum UnknownFields
{
    reject,
    ignore
}

/// Bound the document and choose strict or permissive property handling.
struct DecodeOptions
{
    /// Maximum nested containers, capped at 64.
    uint maxDepth = 64;
    /// Maximum members per object or elements per array, capped at 1024.
    uint maxMembers = 1024;
    /// Maximum document bytes, capped at one MiB.
    size_t maxBytes = 1_048_576;
    /// Policy for unknown properties.
    UnknownFields unknownFields = UnknownFields.reject;
    /// Reject repeated property names when set.
    bool rejectDuplicateKeys = true;
}

/// Configure deterministic output and its container nesting limit.
struct EncodeOptions
{
    /// Sort object keys by their decoded UTF-8 bytes.
    bool canonical = false;
    /// Omit fields marked JsonIgnore from output.
    bool omitIgnored = true;
    /// Maximum nested containers, capped at 64.
    uint maxDepth = 64;
}
