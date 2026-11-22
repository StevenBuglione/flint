/// Caller-owned array control for the arena benchmark harness.
module app;

import arena_probe_harness : cycleCount, failed, marker, measure;

@safe:

pragma(inline, false) private ulong writeBlock(scope ubyte[] block) nothrow @nogc
{
    block[] = 0;
    block[$ - 1] = marker;
    return block.length + block[$ - 1];
}

private ulong allocationTrial(scope ubyte[] backing, size_t bytes, uint count) nothrow @nogc
{
    if (count > backing.length / bytes)
        return failed;

    ulong checksum;
    foreach (index; 0 .. count)
    {
        immutable start = index * bytes;
        checksum += writeBlock(backing[start .. start + bytes]);
    }
    return checksum;
}

pragma(inline, false) private ulong uncheckedRead(scope const(ubyte)[] bytes) nothrow @nogc
{
    return bytes.length + bytes[$ - 1];
}

/// Run the same harness, sizes, storage use and observable result without Flint.
int main()
{
    align(8) ubyte[65_536] backing;
    if (!measure("allocate-64", 64, 64 + marker, () => allocationTrial(backing[], 64, 1)) || !measure("allocate-4096",
            4096, 4096 + marker, () => allocationTrial(backing[], 4096, 1)) || !measure("reset-1000",
            cycleCount * 64, cycleCount * (64 + marker), () => allocationTrial(backing[], 64, cycleCount)))
        return 1;

    scope readable = backing[0 .. 64];
    readable[] = 0;
    readable[$ - 1] = marker;
    return measure("checked-read", 0, 64 + marker, () => uncheckedRead(readable)) ? 0 : 1;
}
