module probe;

import core.time : MonoTime;
import flint.arena : RequestArena, Status;
import std.stdio : writefln;

@safe:

/// Aggregate result consumed by the fixture and its direct-dependency control.
struct Receipt
{
    /// All observed failed constraints.
    size_t total;
    /// Number of failures written to the caller's buffer.
    size_t written;
    /// True when validation passed.
    bool valid;
    /// Order-sensitive digest of the written fields and constraints.
    ulong digest;
}

/// Fixed field-validation workload.
alias ValidateFields = Receipt function(scope const(int)[], bool) @safe nothrow @nogc;

/// Full-string matching workload.
alias Match = bool function(scope const(char)[]) @safe nothrow @nogc;

/// Check a fixture invariant in debug and release.
void verify(bool condition) nothrow @nogc
{
    if (!condition)
        assert(0, "validation probe fixture invariant failed");
}

/// Consume a written field and constraint in declaration order.
ulong consume(ulong digest, string field, string constraint) pure nothrow @nogc
{
    foreach (c; field)
        digest = digest * 131 + c;
    foreach (c; constraint)
        digest = digest * 131 + c;
    return digest;
}

/// Name the fixture DTO field at this index.
string fieldName(uint index) pure nothrow @nogc
{
    // Exactly v000 through v127, shared by the input and the reference.
    return fieldNames[index];
}

private immutable string[128] fieldNames = [
    "v000", "v001", "v002", "v003", "v004", "v005", "v006", "v007", "v008", "v009", "v010", "v011",
    "v012", "v013", "v014", "v015", "v016", "v017", "v018", "v019", "v020", "v021", "v022",
    "v023", "v024", "v025", "v026", "v027", "v028", "v029", "v030", "v031", "v032", "v033", "v034",
    "v035", "v036", "v037", "v038", "v039", "v040", "v041", "v042", "v043", "v044", "v045",
    "v046", "v047", "v048", "v049", "v050", "v051", "v052", "v053", "v054", "v055", "v056", "v057",
    "v058", "v059", "v060", "v061", "v062", "v063", "v064", "v065", "v066", "v067", "v068",
    "v069", "v070", "v071", "v072", "v073", "v074", "v075", "v076", "v077", "v078", "v079", "v080",
    "v081", "v082", "v083", "v084", "v085", "v086", "v087", "v088", "v089", "v090", "v091",
    "v092", "v093", "v094", "v095", "v096", "v097", "v098", "v099", "v100", "v101", "v102", "v103",
    "v104", "v105", "v106", "v107", "v108", "v109", "v110", "v111", "v112", "v113", "v114",
    "v115", "v116", "v117", "v118", "v119", "v120", "v121", "v122", "v123", "v124", "v125", "v126",
    "v127",
];

private struct FieldCase
{
    ValidateFields run;
    bool full;
    bool valid;

    ulong exercise(scope const(int)[] values) const nothrow @nogc
    {
        const actual = run(values, full);
        immutable count = valid ? 0 : values.length;
        verify(actual.valid == valid && actual.total == count && actual.written == (full ? count : 0));
        return actual.digest + (actual.total << 8) + actual.written + cast(uint) actual.valid;
    }
}

private ulong sampleFields(FieldCase workload, size_t width, bool measure)
{
    int[128] input;
    foreach (index, ref value; input[0 .. width])
    {
        immutable magnitude = cast(int)(index % 7);
        value = workload.valid ? magnitude + 1 : -magnitude;
    }

    const first = workload.exercise(input[0 .. width]);
    if (!measure)
        return first;

    enum tranche = 256;
    ulong iterations;
    long elapsed;
    scope const(int)[] sample = input[0 .. width];
    const begin = MonoTime.currTime;
    do
    {
        foreach (_; 0 .. tranche)
            verify(workload.exercise(sample) == first);
        iterations += tranche;
        elapsed = (MonoTime.currTime - begin).total!"nsecs";
    }
    while (elapsed < 100_000_000);
    writefln("fields=%s valid=%s full-output=%s iterations=%s ns=%s", width, workload.valid,
            workload.full, iterations, elapsed);
    return first;
}

private ulong matchPair(Match match, scope char[] input) nothrow @nogc
{
    verify(!match(input));
    input[$ - 1] = 'b';
    const accepted = match(input);
    input[$ - 1] = 'a';
    verify(accepted);
    return input.length + cast(uint) accepted;
}

private double samplePattern(Match match, scope const(char)[] failing)
{
    // Time the failing path, where a backtracking implementation would revisit
    // prefixes. Fixed batching avoids declaring a zero-duration sample.
    ulong iterations;
    long elapsed;
    const begin = MonoTime.currTime;
    do
    {
        foreach (_; 0 .. 32)
            verify(!match(failing));
        iterations += 32;
        elapsed = (MonoTime.currTime - begin).total!"nsecs";
    }
    while (elapsed < 100_000_000);
    const nanosPerInputByte = cast(double) elapsed / iterations / failing.length;
    writefln("pattern-bytes=%s iterations=%s ns=%s ns-per-byte=%s", failing.length, iterations,
            elapsed, nanosPerInputByte);
    return nanosPerInputByte;
}

private ulong exercisePattern(Match match, bool measure)
{
    char[16_384] input;
    input[] = 'a';
    const digest = matchPair(match, input[]);
    if (!measure)
        return digest;

    const perKiB = samplePattern(match, input[0 .. 1_024]);
    foreach (width; [2_048, 4_096, 8_192, 16_384])
    {
        const perByte = samplePattern(match, input[0 .. width]);
        // Doubling the input keeps the normalized cost within a generous
        // timing tolerance on this diagnostic. No data-dependent search budget.
        verify(perByte <= perKiB * 2);
    }
    return digest;
}

private ulong exerciseArena() nothrow @nogc
{
    ubyte[64] bytes;
    scope arena = RequestArena(bytes[]);
    const sample = arena.copyIn(cast(const(ubyte)[]) "hello");
    verify(sample.ok());
    ulong result;
    verify(arena.read(sample.value, (scope const(ubyte)[] view) @safe nothrow @nogc {
            foreach (byteValue; view)
                result = result * 131 + byteValue;
        }) == Status.ok);
    verify(arena.reset() == Status.ok);
    return result;
}

/// Run the common field and pattern workloads while checking every result.
ulong runProbe(ValidateFields[3] validators, Match match, bool measure)
{
    ulong digest = exerciseArena();
    foreach (index, width; [8U, 32U, 128U])
    {
        foreach (valid; [false, true])
        {
            foreach (full; [false, true])
            {
                const workload = FieldCase(validators[index], full, valid);
                digest = digest * 131 + sampleFields(workload, width, measure);
            }
        }
    }
    return digest * 131 + exercisePattern(match, measure);
}
