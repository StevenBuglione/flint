/// Shared timing and result-consumption harness for the arena probes.
module arena_probe_harness;

import core.time : MonoTime;
import std.stdio : writefln;

@safe:

/// Sentinel for a failed runtime correctness check.
enum ulong failed = ulong.max;
/// Number of 64-byte allocations in the bulk reset case.
enum uint cycleCount = 1_000;
/// Byte used to poison reused storage and check the read path.
enum ubyte marker = 0x5a;

/// A single benchmark operation returning an observable workload checksum.
alias Operation = ulong delegate() @safe nothrow @nogc;

/// Run batches for at least 150 ms and verify each operation's checksum.
bool measure(string name, size_t zeroedBytes, ulong expected, scope Operation operation)
{
    if (operation() != expected)
        return false;

    ulong operations;
    ulong checksum;
    long elapsed;
    immutable start = MonoTime.currTime;
    do
    {
        foreach (index; 0 .. 128)
        {
            immutable value = operation();
            if (value != expected)
                return false;
            checksum += value;
        }
        operations += 128;
        elapsed = (MonoTime.currTime - start).total!"nsecs";
    }
    while (elapsed < 150_000_000);

    writefln("%s operations=%s elapsed_ns=%s ns_per_op=%.3f bytes_zeroed_per_op=%s checksum=%s",
            name, operations, elapsed, cast(double) elapsed / operations, zeroedBytes, checksum);
    return true;
}
