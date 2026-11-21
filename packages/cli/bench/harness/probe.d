module probe;

import core.stdc.stdio : printf;
import core.time : MonoTime;
import flint.arena : RequestArena, Status;
import flint.validate : Min, validate;

@safe:

private enum invocations = 10_000;

/// One CLI invocation returning the sum of its typed values.
alias Parse = long function(scope const(char)[], size_t) @safe;

/// Check the fixed benchmark workload in debug and release.
void check(bool passes) nothrow @nogc
{
    if (!passes)
        assert(0, "CLI benchmark fixture invariant failed");
}

// SAFETY: This call returns a scalar thread-local counter and retains no addresses.
private ulong allocationCounter() @trusted nothrow
{
    import core.memory : GC;

    return GC.allocatedInCurrentThread();
}

private struct Seed
{
    @Min(1) int value;
}

private struct Call
{
    string argument;
    int expected;
}

private Call[] prepare(size_t width)
{
    auto calls = new Call[width];
    for (size_t index; index < width; ++index)
    {
        const value = 10 + cast(int) index;
        const valid = Seed(value);
        check(validate(valid, []).valid);
        const text = argumentFor(index, value);

        ubyte[80] scratch;
        scope arena = RequestArena(scratch[]);
        const stored = arena.copyIn(cast(const(ubyte)[]) text);
        check(stored.ok());
        check(arena.read(stored.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
                // The direct dependency validates ownership; no slice is kept.
                check(bytes.length == text.length);
            }) == Status.ok);
        check(arena.reset() == Status.ok);
        calls[index] = Call(text, value);
    }
    return calls;
}

private char digit(size_t value) pure nothrow @nogc
{
    return cast(char)('0' + value % 10);
}

private string argumentFor(size_t index, int value)
{
    char[16] text = "--option-000=000";
    text[9] = digit(index / 100);
    text[10] = digit(index / 10);
    text[11] = digit(index);
    size_t end = 13;
    if (value >= 100)
        text[end++] = digit(value / 100);
    text[end++] = digit(value / 10);
    text[end++] = digit(value);
    return text[0 .. end].idup;
}

// SAFETY: Both C format strings are fixed NUL-terminated literals, with matching scalar arguments.
private void printMeasurement(size_t width, ulong count, ulong setup, ulong allocation, long elapsed) @trusted
{
    printf("declared=%llu invocations=%llu ns/op=%.6f startup-gc=%llu parser-gc=%llu elapsed-ns=%lld\n",
            cast(ulong) width, count, cast(double) elapsed / count, setup, allocation, elapsed);
}

/// Emit the consumed benchmark output in both binaries.
// SAFETY: The C format string is a fixed NUL-terminated literal, with matching scalar arguments.
void printChecksum(size_t width, ulong checksum) @trusted
{
    printf("cli options %llu checksum %llu\n", cast(ulong) width, checksum);
}

private ulong replay(Parse parse, scope const Call[] calls, size_t width)
{
    ulong digest;
    foreach (invocation; 0 .. invocations)
    {
        const item = calls[invocation % calls.length];
        const value = parse(item.argument, width);
        check(value == item.expected);
        digest = digest * 131 + value;
    }
    return digest;
}

/// Check each of 10,000 invocations and report optional local measurements.
ulong runProbe(Parse parse, size_t width, bool measure)
{
    const startAllocation = allocationCounter();
    const calls = prepare(width);
    const setupAllocation = allocationCounter() - startAllocation;
    const starting = MonoTime.currTime;
    const before = allocationCounter();
    const checksum = replay(parse, calls, width);
    ulong passes = 1;
    long elapsed = (MonoTime.currTime - starting).total!"nsecs";
    if (measure)
    {
        while (elapsed < 100_000_000)
        {
            check(replay(parse, calls, width) == checksum);
            ++passes;
            elapsed = (MonoTime.currTime - starting).total!"nsecs";
        }
        const allocated = allocationCounter() - before;
        const count = passes * invocations;
        printMeasurement(width, count, setupAllocation, allocated, elapsed);
    }
    return checksum;
}
