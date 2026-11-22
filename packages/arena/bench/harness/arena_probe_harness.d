/// Shared timing and result-consumption harness for the arena probes.
module arena_probe_harness;

import core.time : MonoTime;
import core.stdc.stdio : printf;

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

    print(name, operations, elapsed, zeroedBytes, checksum);
    return true;
}

// SAFETY: The C format string is a fixed NUL-terminated literal; the name is printed with its
// explicit length and every scalar matches its conversion.
private void print(string name, ulong operations, long elapsed, size_t zeroedBytes, ulong checksum) @trusted
{
    printf("%.*s operations=%llu elapsed_ns=%lld ns_per_op=%.3f bytes_zeroed_per_op=%zu checksum=%llu\n",
            cast(int) name.length, name.ptr, operations, elapsed, cast(double) elapsed / operations,
            zeroedBytes, checksum);
}
