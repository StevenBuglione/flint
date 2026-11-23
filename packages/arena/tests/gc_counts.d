/++
`flint.arena.gc.otherThreadsAllocations`: the per-thread allocation totals the per-request allocation gate reads
(policy/request-allocations.json). The test program runs on the Flint collector (tests/gc_selected.d).
+/
module flint.arena.gc_counts_test;

import core.atomic : atomicLoad, atomicStore;
import core.thread : Thread;
import flint.arena.gc : Allocations, otherThreadsAllocations;

@safe:

private shared int stage;

/// Wait, without allocating, until `stage` reaches `value`.
private void await(int value) @trusted nothrow
{
    while (atomicLoad(stage) < value)
        Thread.yield();
}

@("otherThreadsAllocations counts another thread's allocations exactly, and forgets the thread when it exits")
@system unittest
{
    enum allocations = 1_000;
    atomicStore(stage, 0);
    auto worker = new Thread({
        cast(void) new ubyte[](1); // registers this thread's totals
        atomicStore(stage, 1);
        await(2);
        foreach (i; 0 .. allocations)
        {
            auto block = new ubyte[](100); // NO_SCAN | APPENDABLE: 100 bytes and the length fit a 128-byte block
            block[0] = cast(ubyte) i;
        }
        atomicStore(stage, 3);
        await(4);
    });
    worker.start();
    await(1);

    Allocations before, after, exited;
    assert(otherThreadsAllocations(before), "the Flint collector runs this test program");
    atomicStore(stage, 2);
    await(3);
    assert(otherThreadsAllocations(after));
    assert(after.count - before.count == allocations, "count");
    assert(after.bytes - before.bytes == allocations * 128, "bytes");

    // The caller's own allocations are not counted.
    foreach (_; 0 .. 100)
        cast(void) new ubyte[](16);
    Allocations mine;
    assert(otherThreadsAllocations(mine));
    assert(mine.count == after.count && mine.bytes == after.bytes);

    atomicStore(stage, 4);
    worker.join();
    assert(otherThreadsAllocations(exited));
    assert(exited.count <= after.count - allocations, "an exited thread's totals are forgotten");
}
