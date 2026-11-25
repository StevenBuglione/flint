/++
The permanent start-up region (flint.arena.sys.gc.startup_region): which allocations it takes, that what start-up
drops is retained and never reused, that it keeps heap objects alive, and that everything after `close` goes to the
collector.
+/
module flint.arena.startup_region_test;

import core.atomic : atomicLoad, atomicStore;
import core.memory : GC;
import core.thread : Thread;
import flint.arena.gc : closeStartupRegion, openStartupRegion, startupRegionBlocks, startupRegionBytes;
import flint.arena.sys.gc.startup_region : inStartupRegion, removeStartupRegionProxy;

private shared bool finalized;

private final class Finalized
{
    int value = 7;

    ~this()
    {
        atomicStore(finalized, true);
    }
}

private struct Holder
{
    Object target;
    ubyte[64] canary;
}

@("the start-up region takes only the opening thread's unfinalized allocations, retains what start-up drops, keeps heap objects alive, and hands everything after close to the collector")
@system unittest
{
    assert(openStartupRegion(), "a region opens once");
    // The other tests of this program run on the collector itself.
    scope (exit)
        removeStartupRegionProxy();
    assert(!openStartupRegion(), "a second region is refused");

    // The opening thread's scanned allocations without a finalizer come from the region; the collector does not know
    // them.
    auto numbers = new int*[](10);
    auto pair = new Holder;
    assert(inStartupRegion(numbers.ptr) && inStartupRegion(pair));
    assert(GC.addrOf(numbers.ptr) is null && GC.addrOf(pair) is null);
    foreach (p; numbers)
        assert(p is null, "region memory starts zeroed");

    // A NO_SCAN allocation stays in the collector, which never reads it; the region is scanned whole.
    auto bytes = new ubyte[](4096);
    assert(!inStartupRegion(bytes.ptr) && GC.addrOf(bytes.ptr)!is null);

    // A finalized object goes to the collector, so its destructor still runs.
    auto finalizedObject = new Finalized;
    assert(!inStartupRegion(cast(void*) finalizedObject) && GC.addrOf(cast(void*) finalizedObject)!is null);

    // Another thread's allocations go to the collector even while the region is open.
    void* other;
    auto worker = new Thread({ other = cast(void*) new int*[](10).ptr; });
    worker.start();
    worker.join();
    assert(!inStartupRegion(other) && GC.addrOf(other)!is null);

    // A region block holding the only reference to a heap object keeps it alive across collections.
    pair.target = finalizedObject;
    finalizedObject = null;
    // A block start-up drops: filled with a canary, then forgotten.
    auto dropped = new size_t*[](32);
    foreach (ref slot; dropped)
        slot = cast(size_t*) 0xA5A5A5A5;
    const droppedAddress = cast(size_t) dropped.ptr;
    dropped = null;

    // Appending to a region array copies it (the collector does not know the block, so it cannot grow in place); while
    // the region is open the copy comes from the region too. The original block stays as it was.
    auto grown = numbers;
    grown ~= null;
    assert(grown.ptr !is numbers.ptr && grown.length == 11);
    assert(inStartupRegion(numbers.ptr) && numbers.length == 10);

    // realloc copies a region block out; free ignores one.
    auto block = GC.malloc(48);
    assert(inStartupRegion(block));
    (cast(ubyte*) block)[0 .. 48] = 0x3C;
    auto moved = GC.realloc(block, 4096);
    assert(moved !is null && moved !is block && (cast(ubyte*) moved)[0 .. 48] == (cast(ubyte*) block)[0 .. 48]);
    GC.free(block);
    assert(inStartupRegion(block) && (cast(ubyte*) block)[0] == 0x3C, "freeing a region block changes nothing");

    const regionBytes = startupRegionBytes();
    const blocks = startupRegionBlocks();
    assert(regionBytes >= 10 * (int*).sizeof + Holder.sizeof + 32 * (size_t*).sizeof + 48 && blocks >= 4);

    closeStartupRegion();

    // After close, every allocation goes to the collector.
    auto later = new int*[](10);
    assert(!inStartupRegion(later.ptr) && GC.addrOf(later.ptr)!is null);
    assert(startupRegionBytes() == regionBytes && startupRegionBlocks() == blocks);

    // Collections neither finalize what the region holds nor reuse what it dropped.
    foreach (round; 0 .. 5)
    {
        GC.collect();
        foreach (_; 0 .. 10_000)
        {
            auto churn = new ubyte[](256);
            assert(!inStartupRegion(churn.ptr), "a collector block never lands in the region");
            churn[0] = cast(ubyte) round;
        }
    }
    assert(!atomicLoad(finalized), "the heap object a region block holds stays alive");
    assert((cast(Finalized) pair.target).value == 7);
    auto canary = (cast(size_t*) droppedAddress)[0 .. 32];
    foreach (word; canary)
        assert(word == 0xA5A5A5A5, "a block start-up dropped is retained, never reused");
}
