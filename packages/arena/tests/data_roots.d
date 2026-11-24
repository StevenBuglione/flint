/++
The startup trim of read-only-after-relocation memory from the collector's roots (flint.arena.data_roots): the
RELRO region is no longer scanned, while the writable data around it still is. This test binary runs on the Flint
collector (tests/gc_selected.d); the conservative collector registers and trims ranges through the same interface.
+/
module flint.arena.data_roots_test;

import core.gc.gcinterface : GC, Range;
import core.memory : GC_ = GC;
import flint.arena.data_roots : trimmedRootBytes;

@safe:

private extern (C) GC gc_getProxy() nothrow @nogc;

private final class Anchored
{
    int value;
    shared static bool finalized;

    this(int value)
    {
        this.value = value;
    }

    ~this() @safe nothrow @nogc
    {
        finalized = true;
    }
}

// In .bss: reachable only through the writable data the trim must keep scanning.
private __gshared Anchored anchor;
// In .data, initialised at compile time, and in .bss, initialised by a module constructor.
private __gshared int[3] staticTable = [1, 2, 3];
private __gshared string startupText;

@system shared static this()
{
    startupText = "set at startup";
}

version (linux)
{
    import core.sys.linux.link : dl_iterate_phdr, dl_phdr_info;

    private struct Pages
    {
        size_t begin, end;
    }

    /// The main executable's RELRO pages, computed here independently of the trim.
    private Pages executableRelro() @system
    {
        import core.memory : pageSize;
        import core.sys.elf : PT_GNU_RELRO;

        static extern (C) int first(dl_phdr_info* info, size_t, void* data) nothrow @nogc
        {
            auto pages = cast(Pages*) data;
            foreach (ref header; info.dlpi_phdr[0 .. info.dlpi_phnum])
                if (header.p_type == PT_GNU_RELRO)
                {
                    const start = info.dlpi_addr + header.p_vaddr;
                    pages.begin = start & ~(pageSize - 1);
                    pages.end = (start + header.p_memsz) & ~(pageSize - 1);
                }
            return 1; // the main executable comes first
        }

        Pages pages;
        dl_iterate_phdr(&first, &pages);
        return pages;
    }
}

/// Whether some registered root range covers `address`.
private bool rooted(const(void)* address) @system
{
    bool covered;
    foreach (ref range; gc_getProxy().rangeIter)
        covered = covered || (range.pbot <= address && address < range.ptop);
    return covered;
}

@("the trim removed RELRO from the roots and the writable data around it is still a root")
@system unittest
{
    version (linux)
    {
        // The test binary is linked with RELRO, like every Flint binary on Linux.
        const relro = executableRelro();
        assert(relro.end > relro.begin, "the test binary has no RELRO pages");
        // The writable segment, and so its registered range, may start part way into RELRO's first page.
        import core.memory : pageSize;

        assert(trimmedRootBytes + pageSize > relro.end - relro.begin, "RELRO was not trimmed");
        // No registered range reaches into those pages any more.
        foreach (ref range; gc_getProxy().rangeIter)
            assert(cast(size_t) range.ptop <= relro.begin || cast(size_t) range.pbot >= relro.end,
                    "a root range still covers RELRO");
    }
    assert(rooted(&anchor), "a writable global is no longer a root");
    assert(rooted(&staticTable) && rooted(&startupText));
}

@("an object held only by a global survives collections after the trim; static data set at startup is intact")
@system unittest
{
    anchor = new Anchored(42);
    Anchored.finalized = false;
    foreach (_; 0 .. 4)
    {
        // Churn, so freed memory would be reused if the anchor were not a root.
        foreach (__; 0 .. 10_000)
            cast(void) new ubyte[64];
        GC_.collect();
    }
    assert(!Anchored.finalized && anchor.value == 42, "the object held by a global was collected");
    assert(staticTable == [1, 2, 3] && startupText == "set at startup");
    anchor = null;
}
