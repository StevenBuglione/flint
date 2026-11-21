/// Shared bounded byte sink for serializers and schema generation.
module flint.serde.internal.writer;

import flint.arena : Buffer, Error, RequestArena, Result, Status;
import flint.serde.internal.json_scan : utf8Scalar;

@safe:

/// A write pass, or by default a size-only pass over the same output operations.
struct Writer
{
    private ubyte[] buffer;
    private bool measuring = true;
    /// Output bytes written or counted.
    size_t length;
    /// First output failure.
    Error error;

    /// Borrow the exact-sized writable output from the arena.
    this(return scope ubyte[] output) nothrow @nogc
    {
        buffer = output;
        measuring = false;
    }

    /// Report the first error and retain its output location.
    void fail(Status status, string reason) scope nothrow @nogc
    {
        if (error.code == Status.ok)
            error = Error(status, reason, length);
    }

    /// Emit one byte.
    void put(ubyte byteValue) scope nothrow @nogc
    {
        if (error.code != Status.ok)
            return;
        if (length == size_t.max || (!measuring && length == buffer.length))
        {
            fail(Status.resourceExhausted, "serialization output exceeds its bound");
            return;
        }
        if (!measuring)
            buffer[length] = byteValue;
        ++length;
    }

    /// Emit a fixed fragment.
    void append(scope const(ubyte)[] fragment) scope nothrow @nogc
    {
        foreach (byteValue; fragment)
            put(byteValue);
    }

    /// Emit an unsigned magnitude in base ten.
    void unsignedNumber(ulong magnitude) scope nothrow @nogc
    {
        ubyte[20] digits;
        size_t index = digits.length;
        do
        {
            digits[--index] = cast(ubyte)('0' + magnitude % 10);
            magnitude /= 10;
        }
        while (magnitude != 0);
        append(digits[index .. $]);
    }

    /// Emit a signed integer including its minimum representable value.
    void signedNumber(long value) scope nothrow @nogc
    {
        if (value < 0)
        {
            put('-');
            unsignedNumber(cast(ulong)(-(value + 1)) + 1);
        }
        else
            unsignedNumber(cast(ulong) value);
    }

    /// Emit a UTF-8 string with JSON quoting and control-character escapes.
    void stringValue(scope const(ubyte)[] value, bool toml = false) scope nothrow @nogc
    {
        enum hex = "0123456789abcdef";
        put('"');
        size_t offset;
        while (offset < value.length)
        {
            immutable position = offset;
            uint scalar;
            if (!utf8Scalar(value, offset, scalar))
            {
                fail(Status.invalidArgument, "invalid UTF-8 in serialization input");
                return;
            }
            switch (scalar)
            {
            case '"':
                append(cast(const(ubyte)[]) "\\\"");
                break;
            case '\\':
                append(cast(const(ubyte)[]) "\\\\");
                break;
            case '\b':
                append(cast(const(ubyte)[]) "\\b");
                break;
            case '\t':
                append(cast(const(ubyte)[]) "\\t");
                break;
            case '\n':
                append(cast(const(ubyte)[]) "\\n");
                break;
            case '\f':
                append(cast(const(ubyte)[]) "\\f");
                break;
            case '\r':
                append(cast(const(ubyte)[]) "\\r");
                break;
            default:
                if (scalar < 0x20 || (toml && scalar == 0x7f))
                {
                    append(cast(const(ubyte)[]) "\\u00");
                    put(hex[(scalar >> 4) & 0xf]);
                    put(hex[scalar & 0xf]);
                }
                else
                    append(value[position .. offset]);
                break;
            }
        }
        put('"');
    }
}

private alias Emission = void delegate(ref scope Writer) @safe nothrow @nogc;

/// Preflight the complete output, then emit into an exact-sized arena allocation.
Result!Buffer writeArenaBuffer(ref scope RequestArena arena, scope Emission emit) nothrow @nogc
{
    Writer sizing;
    emit(sizing);
    if (sizing.error.code != Status.ok)
        return Result!Buffer(Buffer.init, sizing.error);
    auto allocation = arena.allocate(sizing.length, 1);
    if (!allocation.ok())
        return allocation;

    Status emission;
    immutable status = arena.write(allocation.value, (scope ubyte[] output) @safe nothrow @nogc {
        scope writer = Writer(output);
        emit(writer);
        emission = writer.error.code;
        if (emission == Status.ok && writer.length != output.length)
            emission = Status.conflict;
    });
    if (status != Status.ok)
        return Result!Buffer(Buffer.init, Error(status, "invalid serialization output buffer"));
    if (emission != Status.ok)
        return Result!Buffer(Buffer.init, Error(emission, "serialization output changed after sizing"));
    return allocation;
}
