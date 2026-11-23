/++
The arena test program runs on Flint's collector: `rt_options` selects it, so every test in this binary, and
the collector's own ported unittests, allocate and collect through it.
+/
module flint.arena.gc_selected_test;

import core.gc.gcinterface : GC;
import flint.arena.gc : collectorName;

@safe:

/// druntime reads this before `main`: the test program starts on the Flint collector.
extern (C) __gshared string[] rt_options = ["gcopt=gc:" ~ collectorName];

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
