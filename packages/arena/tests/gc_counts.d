/++
The allocation counter of `flint.arena.gc`, which the per-request allocation gate reads
(policy/request-allocations.json): a counting proxy over the running collector.
+/
module flint.arena.gc_counts_test;

import core.atomic : atomicLoad, atomicStore;
import core.memory : GC;
import core.thread : Thread;
import flint.arena.gc : Allocations, installAllocationCounter, otherThreadsAllocations,
    recordAllocationSites, thisThreadAllocations, topAllocationSites, uninstallAllocationCounter;

@safe:

private shared int stage;

/// Wait, without allocating, until `stage` reaches `value`.
private void await(int value) @trusted nothrow
{
    while (atomicLoad(stage) < value)
        Thread.yield();
}

/// Allocates `count` 100-byte arrays: a recognizable call site.
private void allocateHundreds(size_t count)
{
    foreach (i; 0 .. count)
    {
        auto block = new ubyte[](100);
        block[0] = cast(ubyte) i;
    }
}

@("the allocation counter counts another thread's allocations exactly, names their site, forgets an exited thread")
@system unittest
{
    enum allocations = 1_000;
    Allocations unused;
    assert(!otherThreadsAllocations(unused), "nothing is counted before the proxy is installed");
    assert(installAllocationCounter());
    scope (exit)
        uninstallAllocationCounter();
    assert(!installAllocationCounter(), "installed once");

    atomicStore(stage, 0);
    auto worker = new Thread({
        cast(void) new ubyte[](1); // registers this thread
        atomicStore(stage, 1);
        await(2);
        allocateHundreds(allocations);
        atomicStore(stage, 3);
        await(4);
    });
    worker.start();
    scope (exit)
    {
        atomicStore(stage, 4); // release the worker even when an assertion below fails
        worker.join();
    }
    await(1);

    Allocations before, after;
    assert(otherThreadsAllocations(before));
    recordAllocationSites(true);
    atomicStore(stage, 2);
    await(3);
    recordAllocationSites(false);
    assert(otherThreadsAllocations(after));
    assert(after.count - before.count == allocations, "count");
    assert(after.bytes - before.bytes >= allocations * 100, "bytes");
    const sites = topAllocationSites(3);
    version (linux)
    {
        assert(sites.length >= 1);
        import std.algorithm.searching : canFind;

        assert(sites[0].canFind("allocateHundreds") && sites[0].canFind("1000"), sites[0]);
    }

}

@("the allocation counter keeps an exited thread's totals, and a reinstall starts again from zero")
@system unittest
{
    assert(installAllocationCounter());
    auto worker = new Thread({ allocateHundreds(100); });
    worker.start();
    worker.join();
    Allocations exited;
    assert(otherThreadsAllocations(exited));
    assert(exited.count >= 100 && exited.bytes >= 100 * 100, "a server's workers exit before the run is reported");
    uninstallAllocationCounter();
    assert(installAllocationCounter());
    scope (exit)
        uninstallAllocationCounter();
    Allocations fresh;
    assert(otherThreadsAllocations(fresh));
    assert(fresh.count == 0, "an earlier installation's exited threads are not counted again");
}

@("the counter's bytes on a thread equal druntime's own allocatedInCurrentThread for the same allocations")
@system unittest
{
    assert(installAllocationCounter());
    scope (exit)
        uninstallAllocationCounter();
    Allocations before, after;
    assert(thisThreadAllocations(before));
    const druntimeBefore = GC.stats().allocatedInCurrentThread;
    allocateHundreds(500);
    auto text = "x";
    foreach (i; 0 .. 200)
        text ~= 'y'; // appends: new blocks and in-place extensions
    auto object = new Object;
    const druntimeAfter = GC.stats().allocatedInCurrentThread;
    assert(thisThreadAllocations(after));
    assert(after.bytes - before.bytes == druntimeAfter - druntimeBefore, "bytes match druntime's count exactly");
    assert(after.count - before.count >= 501);
    assert(text.length == 201 && object !is null);
}
