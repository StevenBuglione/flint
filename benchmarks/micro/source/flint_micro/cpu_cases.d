/// Arena, canonical serialization and frozen validation microbenchmark inputs.
module flint_micro.cpu_cases;

import flint.arena : Buffer, RequestArena, Status, Text;
import flint.serde : decodeInto, decodeTomlInto, encodeJson, encodeToml;
import flint.validate : Max, Min, NotBlank, Size, Violation, validate;
import flint_bench_rest.profile : Message, jsonBody;
import flint_micro.timing : BatchResult;

@safe:

/// Arena and serialization workloads use separate fixed 64 KiB regions.
enum arenaBytes = 65_536;
private enum arenaPattern = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!?";
private enum tomlBody = "message = \"hello\"\nn = 42\n";

private struct Decoded
{
    Text message;
    int n;
}

private struct Checked
{
    @NotBlank
    @Size(2, 4)
    string label;
    @Min(1)
    @Max(9)
    int score;
}

private struct ValidationCase
{
    Checked value;
    size_t failures;
}

private immutable ValidationCase[8] validationCorpus = [
    ValidationCase(Checked("ab", 5), 0), ValidationCase(Checked(" \t", 5), 1),
    ValidationCase(Checked("\u00a0\u2003", 5), 1), ValidationCase(Checked("abcde", 20), 2),
    ValidationCase(Checked("xy", -1), 1), ValidationCase(Checked("a", 5), 1),
    ValidationCase(Checked("é𝄞", 3), 0), ValidationCase(Checked("", 0), 3),
];

/// A startup-owned reusable workspace for the four CPU workflows.
final class CpuCases
{
    private align(8) ubyte[arenaBytes] blocks;
    private align(8) ubyte[arenaBytes] wire;
    private RequestArena* blockArena;
    private RequestArena* wireArena;

    /// Prepare both arenas before measuring any operation.
    this()
    {
        blockArena = new RequestArena(blocks[]);
        wireArena = new RequestArena(wire[]);
    }

    /// Verify the complete copied pattern, then reject that handle after resetting the arena.
    bool verifyArena() nothrow @nogc
    {
        ref arena = *blockArena;
        const handle = filledBlock(arena);
        if (handle.length() != arenaPattern.length)
            return false;
        if (!matches(arena, handle, arenaPattern))
            return false;
        if (arena.reset() != Status.ok)
            return false;
        return arena.read(handle, (scope const(ubyte)[]) @safe nothrow @nogc {}) == Status.invalidArgument;
    }

    /// Allocate, write, read and reset one generation per operation.
    BatchResult arena(uint count) nothrow @nogc
    {
        ref region = *blockArena;
        ulong result;
        foreach (_; 0 .. count)
        {
            const handle = filledBlock(region);
            if (handle.length() != arenaPattern.length)
                return BatchResult.init;
            ulong observed;
            const read = region.read(handle, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
                observed = bytes.length + cast(ulong) bytes[0] + bytes[$ - 1];
            });
            if (read != Status.ok || region.reset() != Status.ok)
                return BatchResult.init;
            result += observed;
        }
        return BatchResult(count, result);
    }

    /// Encode and decode the byte-for-byte canonical REST DTO.
    BatchResult serde(uint count) nothrow @nogc
    {
        return serialization!false(count);
    }

    /// Measure the TOML round trip only in the named diagnostic series.
    BatchResult toml(uint count) nothrow @nogc
    {
        return serialization!true(count);
    }

    private BatchResult serialization(bool toml)(uint count) nothrow @nogc
    {
        ref region = *wireArena;
        ulong result;
        foreach (_; 0 .. count)
        {
            const observed = roundTrip!toml(region);
            if (!observed || region.reset() != Status.ok)
                return BatchResult.init;
            result += observed;
        }
        return BatchResult(count, result);
    }

    /// Validate the ordered corpus, checking stored and total violation counts on every DTO.
    BatchResult validation(uint count) nothrow @nogc
    {
        ulong checksum;
        Violation[3] violations;
        foreach (index; 0 .. count)
        {
            const example = validationCorpus[index % validationCorpus.length];
            const checked = validate(example.value, violations[]);
            if (checked.valid != (example.failures == 0) || checked.written != example.failures
                    || checked.total != example.failures)
                return BatchResult.init;
            checksum += 1 + checked.total;
        }
        return BatchResult(count, checksum);
    }
}

private Buffer filledBlock(ref scope RequestArena arena) nothrow @nogc
{
    const result = arena.allocate(arenaPattern.length);
    if (!result.ok())
        return Buffer.init;
    const status = arena.write(result.value, (scope ubyte[] bytes) @safe nothrow @nogc {
        bytes[] = cast(const(ubyte)[]) arenaPattern;
    });
    return status == Status.ok ? result.value : Buffer.init;
}

private bool matches(ref scope RequestArena arena, Buffer handle, string expected) nothrow @nogc
{
    bool equal;
    const status = arena.read(handle, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        equal = bytes == cast(const(ubyte)[]) expected;
    });
    return status == Status.ok && equal;
}

private ulong roundTrip(bool toml)(ref scope RequestArena arena) nothrow @nogc
{
    Message value;
    static if (toml)
    {
        const encoded = encodeToml(value, arena);
        enum expected = tomlBody;
    }
    else
    {
        const encoded = encodeJson(value, arena);
        enum expected = jsonBody;
    }
    if (!encoded.ok())
        return 0;
    Decoded decoded;
    bool decodedOk;
    const status = arena.read(encoded.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        if (bytes != cast(const(ubyte)[]) expected)
            return;
        static if (toml)
            const decodedStatus = decodeTomlInto(bytes, decoded, arena);
        else
            const decodedStatus = decodeInto(bytes, decoded, arena);
        decodedOk = decodedStatus.code == Status.ok;
    });
    if (status != Status.ok || !decodedOk || decoded.n != value.n)
        return 0;
    if (!matches(arena, decoded.message.bytes, value.message))
        return 0;
    return cast(ulong) decoded.n + expected.length + decoded.message.bytes.length();
}
