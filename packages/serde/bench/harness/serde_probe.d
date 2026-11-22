/// Shared fixed inputs and observable result consumption for Serde probes.
module serde_probe;

import core.stdc.stdio : printf;
import core.time : MonoTime;
import flint.arena : Buffer, RequestArena, Status;

@safe:

/// Number of properties in the monomorphic payload.
enum payloadFields = 3;
/// Fixed payload sizes from the Serde package specification.
immutable size_t[3] fixtureSizes = [64, 1_024, 16_384];

/// Successful observations have consumed every output byte.
struct Observation
{
    /// Sum of returned bytes, including JSON punctuation.
    ulong checksum;
    /// Peak arena usage recorded for the operation.
    size_t peak;
    /// Whether all claimed output bytes matched the expected fixture.
    bool accepted;
}

/// A nonallocating operation for an already-built fixture.
alias Operation = Observation delegate() @safe nothrow @nogc;

/// Materialize a fixed-sized payload with or without escaped characters.
ubyte[] payload(size_t size, bool escaped)
{
    enum prefix = `{"code":17,"text":"`;
    enum suffix = `","ready":true}`;
    auto bytes = new ubyte[size];
    const boundary = size - suffix.length;
    bytes[0 .. prefix.length] = cast(const(ubyte)[]) prefix;
    bytes[boundary .. $] = cast(const(ubyte)[]) suffix;
    bytes[prefix.length .. boundary] = 'a';
    if (escaped)
    {
        for (size_t index = prefix.length; index + 1 < boundary; index += 2)
        {
            bytes[index] = '\\';
            bytes[index + 1] = index % 4 < 2 ? 'n' : 't';
        }
    }
    return bytes;
}

/// Construct the schema expected of a DTO with this number of unsigned fields.
string schema(size_t fields)
{
    string text = `{"type":"object","properties":{`;
    foreach (index; 1 .. fields + 1)
    {
        if (index > 1)
            text ~= ",";
        char[3] digits;
        digits[0] = cast(char)('0' + index / 100);
        digits[1] = cast(char)('0' + index / 10 % 10);
        digits[2] = cast(char)('0' + index % 10);
        text ~= "\"field" ~ digits[] ~ "\":";
        text ~= `{"type":"integer","minimum":0,"maximum":4294967295}`;
    }
    return text ~ `},"required":[],"additionalProperties":false}`;
}

/// Consume the exact bytes of one returned arena buffer.
Observation observe(ref scope RequestArena arena, Buffer data, scope const(ubyte)[] expected) nothrow @nogc
{
    Observation observation;
    observation.peak = arena.stats().peak;
    const status = arena.read(data, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        if (bytes.length != expected.length)
            return;
        foreach (index, byteValue; bytes)
        {
            if (byteValue != expected[index])
                return;
            observation.checksum += byteValue;
        }
        observation.accepted = true;
    });
    if (status != Status.ok)
        observation.accepted = false;
    return observation;
}

/// Measure the fixed operation in batches spanning at least 150 ms.
bool measure(string label, size_t size, size_t fields, scope Operation operation)
{
    const warmup = operation();
    if (!warmup.accepted)
        return false;

    ulong checksum;
    size_t peak;
    ulong operations;
    long elapsed;
    const start = MonoTime.currTime;
    do
    {
        foreach (index; 0 .. 32)
        {
            const observation = operation();
            if (!observation.accepted)
                return false;
            checksum += observation.checksum;
            if (peak < observation.peak)
                peak = observation.peak;
        }
        operations += 32;
        elapsed = (MonoTime.currTime - start).total!"nsecs";
    }
    while (elapsed < 150_000_000);
    report(label, size, fields, operations, elapsed, peak, checksum);
    return true;
}

// SAFETY: The C format string is a fixed NUL-terminated literal; the label is printed with its
// explicit length and every scalar matches its conversion.
private void report(string label, size_t size, size_t fields, ulong operations, long elapsed,
        size_t peak, ulong checksum) @trusted nothrow @nogc
{
    printf("%.*s bytes=%zu fields=%zu ops=%llu elapsed_ns=%lld bytes_per_second=%.2f ns_per_field=%.2f peak=%zu "
            ~ "checksum=%llu\n", cast(int) label.length,
            label.ptr, size, fields, operations, elapsed,
            cast(double) size * operations * 1e9 / elapsed, cast(double) elapsed / operations / fields, peak, checksum);
}
