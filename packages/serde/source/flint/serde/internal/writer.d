/// Shared bounded byte sink for serializers and schema generation.
module flint.serde.internal.writer;

import flint.arena : Buffer, Error, RequestArena, Result, Status;
import flint.serde.internal.json_scan : copyInto, readUtf8;

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
    pragma(inline, true) void put(ubyte byteValue) scope nothrow @nogc
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
        if (fragment.length < 16)
        {
            // Short fragments, such as escapes and punctuation, avoid the bulk-copy call overhead.
            foreach (byteValue; fragment)
                put(byteValue);
            return;
        }
        if (error.code != Status.ok)
            return;
        immutable room = measuring ? size_t.max - length : buffer.length - length;
        if (fragment.length > room)
        {
            // Match byte-at-a-time emission: fill to the bound, then report it.
            if (!measuring)
                copyInto(buffer[length .. $], fragment[0 .. room]);
            length += room;
            fail(Status.resourceExhausted, "serialization output exceeds its bound");
            return;
        }
        if (!measuring)
            copyInto(buffer[length .. length + fragment.length], fragment);
        length += fragment.length;
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
            immutable run = offset;
            offset = plainRun(value, offset, toml);
            if (offset != run)
                append(value[run .. offset]);
            if (offset == value.length)
                break;

            // The run stops at an ASCII byte that needs an escape or at invalid UTF-8.
            immutable scalar = value[offset];
            if (scalar >= 0x80)
            {
                fail(Status.invalidArgument, "invalid UTF-8 in serialization input");
                return;
            }
            ++offset;
            put('\\');
            switch (scalar)
            {
            case '"':
            case '\\':
                put(cast(ubyte) scalar);
                break;
            case '\b':
                put('b');
                break;
            case '\t':
                put('t');
                break;
            case '\n':
                put('n');
                break;
            case '\f':
                put('f');
                break;
            case '\r':
                put('r');
                break;
            default:
                put('u');
                put('0');
                put('0');
                put(hex[(scalar >> 4) & 0xf]);
                put(hex[scalar & 0xf]);
                break;
            }
        }
        put('"');
    }
}

// End of the longest run needing no escape, validating multibyte UTF-8 in place.
pragma(inline, true) private size_t plainRun(scope const(ubyte)[] value, size_t offset, bool toml) nothrow @nogc
{
    while (offset < value.length)
    {
        immutable byteValue = value[offset];
        if (byteValue >= 0x80)
        {
            size_t next = offset;
            if (!readUtf8(value, next).valid)
                break;
            offset = next;
        }
        else if (byteValue >= 0x20 && byteValue != '"' && byteValue != '\\' && (byteValue != 0x7f || !toml))
            ++offset;
        else
            break;
    }
    return offset;
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
