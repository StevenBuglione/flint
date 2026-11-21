module probe;

import core.time : MonoTime;
import flint.arena : RequestArena, Status;
import std.stdio : writefln;

@safe:

private enum traceBytes = 10 * 1024 * 1024;
private enum prefix = "a🦊\x1b[A\x1b[1;5D\x1b[<0;12;34M\x1b[200~text\x1b[31m\x1b[201~\x03";
private enum suffix = "abcdefghijklmnopqrstuv"[0 .. 64 - prefix.length];

/// One 64-byte chunk of the input trace. Record boundaries may cross reads.
enum record = prefix ~ suffix;

/// Check a fixture result even under release builds.
void check(bool passes) nothrow @nogc
{
    if (!passes)
        assert(0, "terminal probe fixture invariant failed");
}

/// Aggregate observed event identity and data in arrival order.
struct Digest
{
    /// Rolling fingerprint.
    ulong value;
    /// Number of events consumed.
    ulong events;

    /// Consume a normalized event category.
    void start(uint kind) nothrow @nogc
    {
        ++events;
        add(kind);
    }

    /// Consume one event field.
    void add(uint field) nothrow @nogc
    {
        value = value * 131 + field;
    }

    /// Consume the exact bytes in an owned paste.
    void text(scope const(char)[] data) nothrow @nogc
    {
        add(cast(uint) data.length);
        foreach (byteValue; data)
            add(byteValue);
    }
}

/// One 10 MiB decoder or reference replay.
alias Replay = Digest function(scope const(char)[] bytes, size_t chunk) @safe;

/// Reference event sequence for one fixed trace record.
void expectRecord(ref Digest stream) nothrow @nogc
{
    expectKey(stream, 1, 'a', 0);
    expectKey(stream, 1, '🦊', 0);
    expectKey(stream, 6, 0, 0);
    expectKey(stream, 8, 0, 1);
    stream.start(3);
    stream.add(12);
    stream.add(34);
    stream.add(0);
    stream.add(1);
    stream.start(2);
    stream.text("text\x1b[31m");
    stream.start(5);
    foreach (byteValue; suffix)
        expectKey(stream, 1, byteValue, 0);
}

private void expectKey(ref Digest stream, uint code, uint scalar, uint modifiers) nothrow @nogc
{
    stream.start(0);
    stream.add(code);
    stream.add(scalar);
    stream.add(modifiers);
}

private void holdRecord(scope char[] bytes) nothrow @nogc
{
    // Prepare the same test input through the direct arena dependency.
    ubyte[80] backing;
    scope arena = RequestArena(backing[]);
    const input = arena.copyIn(cast(const(ubyte)[]) record);
    check(input.ok());
    check(arena.read(input.value, (scope const(ubyte)[] source) @safe nothrow @nogc {
            bytes[] = cast(const(char)[]) source;
        }) == Status.ok);
    check(arena.reset() == Status.ok);
}

private Digest replayChecked(Replay replay, scope const(char)[] trace, size_t chunk, Digest expected)
{
    const actual = replay(trace, chunk);
    check(actual == expected);
    return actual;
}

// SAFETY: The runtime returns the calling thread's scalar counter with no borrowed storage.
private ulong allocationCounter() @trusted nothrow
{
    import core.memory : GC;

    return GC.allocatedInCurrentThread();
}

private Digest sample(Replay replay, scope const(char)[] trace, size_t chunk, Digest expected)
{
    Digest observed;
    ulong passes;
    long elapsed;
    const begin = MonoTime.currTime;
    const before = allocationCounter();
    do
    {
        observed = replayChecked(replay, trace, chunk, expected);
        ++passes;
        elapsed = (MonoTime.currTime - begin).total!"nsecs";
    }
    while (elapsed < 100_000_000);

    const allocated = allocationCounter() - before;
    const processed = passes * trace.length;
    writefln("read-size=%s bytes=%s MiB/s=%s allocated=%s elapsed-ns=%s", chunk, processed,
            cast(double) processed / (1024 * 1024) * 1_000_000_000 / elapsed, allocated, elapsed);
    return observed;
}

/// Execute the full shared input workload and return the verified checksum.
ulong runProbe(Replay replay, bool measure)
{
    static assert(record.length == 64 && traceBytes % record.length == 0);
    char[record.length] seed;
    holdRecord(seed[]);
    auto trace = new char[traceBytes];
    Digest expected;
    foreach (offset; 0 .. traceBytes / record.length)
    {
        trace[offset * record.length .. (offset + 1) * record.length] = seed[];
        expectRecord(expected);
    }

    Digest observed;
    foreach (chunk; [1, 4, 4096])
        observed = measure ? sample(replay, trace[], chunk, expected) : replayChecked(replay, trace[], chunk, expected);
    return observed.value;
}
