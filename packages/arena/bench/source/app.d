/// Real arena allocation, reset and checked-handle read measurements.
module app;

import arena_probe_harness : cycleCount, failed, marker, measure;
import flint.arena : Buffer, RequestArena, Status;

@safe:

private ulong allocateAndCheck(ref scope RequestArena arena, size_t bytes) nothrow @nogc
{
    auto block = arena.allocate(bytes);
    if (!block.ok() || block.value.length() != bytes)
        return failed;

    ulong checksum = failed;
    immutable writeStatus = arena.write(block.value, (scope ubyte[] value) @safe nothrow @nogc {
        if (value[$ - 1] == 0)
        {
            value[$ - 1] = marker;
            checksum = value.length + value[$ - 1];
        }
    });
    return writeStatus == Status.ok ? checksum : failed;
}

private ulong allocationTrial(ref scope RequestArena arena, size_t bytes, uint count) nothrow @nogc
{
    ulong checksum;
    foreach (index; 0 .. count)
    {
        immutable value = allocateAndCheck(arena, bytes);
        if (value == failed)
            return failed;
        checksum += value;
    }
    return arena.reset() == Status.ok ? checksum : failed;
}

private ulong checkedRead(ref scope RequestArena arena, Buffer handle) nothrow @nogc
{
    ulong checksum;
    immutable readStatus = arena.read(handle, (scope const(ubyte)[] value) @safe nothrow @nogc {
        checksum = value.length + value[$ - 1];
    });
    return readStatus == Status.ok ? checksum : failed;
}

/// Exit nonzero on any failed behavior check, including in release builds.
int main()
{
    align(8) ubyte[65_536] backing;
    scope arena = RequestArena(backing[]);
    if (!measure("allocate-64", 64, 64 + marker, () => allocationTrial(arena, 64, 1))
            || !measure("allocate-4096", 4096, 4096 + marker, () => allocationTrial(arena, 4096, 1))
            || !measure("reset-1000",
                cycleCount * 64, cycleCount * (64 + marker), () => allocationTrial(arena, 64, cycleCount)))
        return 1;

    ubyte[64] sample;
    sample[$ - 1] = marker;
    auto readable = arena.copyIn(sample[]);
    if (!readable.ok() || !measure("checked-read", 0, 64 + marker, () => checkedRead(arena, readable.value)))
        return 1;

    return arena.reset() == Status.ok && checkedRead(arena, readable.value) == failed ? 0 : 1;
}
