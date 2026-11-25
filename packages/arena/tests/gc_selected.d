/++
The arena test program runs on Flint's collector: `rt_options` selects it, so every test in this binary, and
the collector's own ported unittests, allocate and collect through it.
+/
module flint.arena.gc_selected_test;

import core.gc.gcinterface : GC;
import flint.arena.gc : collectorName;

@safe:

/// druntime reads this before `main`: the test program starts on the Flint collector.
// heapSizeFactor:4 overrides the default's 3 (tests/fixed_pools.d checks that the program's own option wins).
extern (C) __gshared string[] rt_options = ["gcopt=gc:" ~ collectorName ~ " heapSizeFactor:4"];

private extern (C) GC gc_getProxy() nothrow @nogc;

@("rt_options selects Flint's collector, and it allocates, collects and frees")
@system unittest
{
    import core.memory : CoreGC = GC;

    // druntime starts the selected collector on the first allocation (until then it is a ProtoGC placeholder).
    // The proxy then forwards to the instance, which is the ported collector's class.
    cast(void) new ubyte[](16);
    const instance = gc_getProxy();
    assert(instance !is null);
    assert(typeid(cast(Object) instance).name == "flint.arena.sys.gc.collector.ConservativeGC",
            typeid(cast(Object) instance).name);

    const before = CoreGC.stats();
    foreach (i; 0 .. 100_000)
    {
        auto block = new ubyte[](64 + i % 256);
        block[0] = cast(ubyte) i;
    }
    CoreGC.collect();
    const after = CoreGC.stats();
    assert(after.freeSize > 0, "a collection freed the garbage");
    assert(CoreGC.profileStats().numCollections > 0);
    assert(before.usedSize < 64 * 1024 * 1024 && after.usedSize < 64 * 1024 * 1024);
}

@("full collection phase totals cover a forced collection")
@system unittest
{
    import core.memory : CoreGC = GC;
    import flint.arena.gc : pauseProfile;

    const before = pauseProfile();
    CoreGC.collect();
    const after = pauseProfile();
    assert(after.collections == before.collections + 1);
    const phases = (after.suspendNs - before.suspendNs) + (after.markNs - before.markNs) + (
            after.resumeNs - before.resumeNs) + (after.sweepNs - before.sweepNs);
    assert(after.markNs > before.markNs && after.sweepNs > before.sweepNs);
    assert(after.lockNs - before.lockNs >= phases);
}

@("prediction counts a spanning object once and excludes pointer-free payloads")
@system unittest
{
    import core.gc.config : config;
    import core.memory : CoreGC = GC;
    import flint.arena.gc : pauseProfile;

    const entering = pauseProfile();
    if (config.gc != "flint-predict")
    {
        assert(entering.predictions == 0 && entering.censuses == 0);
        return;
    }

    enum span = 8 * 1024 * 1024;
    auto obj = cast(ubyte*) CoreGC.calloc(span);
    auto raw = cast(ubyte*) CoreGC.calloc(span * 2, CoreGC.BlkAttr.NO_SCAN);
    CoreGC.addRoot(obj);
    CoreGC.addRoot(raw);
    scope (exit)
    {
        CoreGC.removeRoot(raw);
        CoreGC.removeRoot(obj);
    }
    CoreGC.collect();
    const before = pauseProfile();
    obj[4096] = obj[513 * 4096] = 7; // different pagemap batches in the same large block
    raw[0] = raw[4096] = 9;
    CoreGC.collect();
    const after = pauseProfile();
    assert(after.predictions == before.predictions + 1 && after.rootScanNs > before.rootScanNs);
    assert(after.oldScanNs > before.oldScanNs);
    version (linux)
    {
        assert(after.censuses == before.censuses + 1 && after.censusNs > before.censusNs);
        assert(after.dirtyPages >= before.dirtyPages + 2 && after.dirtyObjects > before.dirtyObjects);
        assert(after.scannablePages - before.scannablePages >= after.dirtyPages - before.dirtyPages);
        assert(after.scannableObjects - before.scannableObjects >= after.dirtyObjects - before.dirtyObjects);
        assert(after.scannableBytes - before.scannableBytes >= after.dirtyBytes - before.dirtyBytes);
        const bytes = after.dirtyBytes - before.dirtyBytes;
        assert(bytes >= span && bytes < 2 * span, "large object counted twice or NO_SCAN included");
        assert(after.dirtyScanBytes - before.dirtyScanBytes < span, "clean portions counted as dirty");
    }
}
