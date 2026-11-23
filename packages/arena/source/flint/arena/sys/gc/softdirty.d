/++
The kernel's record of written pages, for the Flint collector's mostly-concurrent marking (docs/spring/phase1/gc.md,
section 3a; the technique of bdwgc's SOFT_VDB, implemented here from the kernel's documentation,
Documentation/admin-guide/mm/soft-dirty.rst and pagemap.rst).

Writing `4` to /proc/self/clear_refs clears the soft-dirty bit of every page of the process and write-protects it, so
the next write to a page faults once and sets the bit again; bit 55 of a page's 64-bit /proc/self/pagemap entry is
that bit. D emits no write barriers, so this is how a collector learns which pages the program wrote while it was
marking. Linux only: elsewhere, and where /proc is unavailable, `open` fails and the collector marks with the world
stopped, as druntime does.
+/
module flint.arena.sys.gc.softdirty;

@system: // Flint: system calls on the collector's own descriptors, in an allowlisted low-level directory

version (FlintCollector)  :  // Flint: opt-in, with the collector
version (linux)  :  // the kernel's soft-dirty tracking

/// The pagemap entries read per system call.
enum softDirtyBatch = 512;

private enum ulong softDirtyBit = 1UL << 55;
private enum size_t pageBytes = 4096;

/// The two /proc descriptors, opened once per collector.
struct SoftDirty
{
    private int clearRefs = -1;
    private int pagemap = -1;

    /// Open /proc/self/clear_refs and /proc/self/pagemap; false when either is unavailable.
    bool open() nothrow @nogc
    {
        import core.sys.posix.fcntl : O_CLOEXEC, O_RDONLY, O_WRONLY, open_ = open;

        if (clearRefs >= 0)
            return true;
        clearRefs = open_("/proc/self/clear_refs", O_WRONLY | O_CLOEXEC);
        pagemap = open_("/proc/self/pagemap", O_RDONLY | O_CLOEXEC);
        if (clearRefs >= 0 && pagemap >= 0)
            return true;
        close();
        return false;
    }

    /// Whether `open` succeeded.
    bool ready() const nothrow @nogc
    {
        return clearRefs >= 0;
    }

    /// Clear every page's soft-dirty bit; false when the kernel refused.
    bool clear() nothrow @nogc
    {
        import core.sys.posix.unistd : pwrite;

        static immutable char[1] four = "4";
        return clearRefs >= 0 && pwrite(clearRefs, four.ptr, 1, 0) == 1;
    }

    /++
    Whether each of the `dirty.length` pages from the page-aligned `start` was written since the last `clear`;
    `dirty.length` is at most `softDirtyBatch`. False when the kernel's answer was short or refused: the caller then
    treats every page as written.
    +/
    bool read(const(void)* start, bool[] dirty) nothrow @nogc
    {
        import core.sys.posix.unistd : pread;

        assert(dirty.length <= softDirtyBatch && (cast(size_t) start & (pageBytes - 1)) == 0);
        ulong[softDirtyBatch] entries = void;
        const bytes = dirty.length * ulong.sizeof;
        const offset = cast(long)(cast(size_t) start / pageBytes * ulong.sizeof);
        if (pagemap < 0 || pread(pagemap, entries.ptr, bytes, offset) != cast(long) bytes)
            return false;
        foreach (i, ref page; dirty)
            page = (entries[i] & softDirtyBit) != 0;
        return true;
    }

    /// Close both descriptors.
    void close() nothrow @nogc
    {
        import core.sys.posix.unistd : close_ = close;

        if (clearRefs >= 0)
            close_(clearRefs);
        if (pagemap >= 0)
            close_(pagemap);
        clearRefs = pagemap = -1;
    }
}

unittest
{
    import core.sys.posix.sys.mman : MAP_ANON, MAP_FAILED, MAP_PRIVATE, PROT_READ, PROT_WRITE, mmap, munmap;

    SoftDirty tracker;
    if (!tracker.open())
        return; // no /proc: the collector marks with the world stopped
    scope (exit)
        tracker.close();
    // Its own small mapping, so a transparent huge page (dirty as a whole) cannot hold it.
    auto block = mmap(null, 4 * pageBytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(block != MAP_FAILED);
    scope (exit)
        munmap(block, 4 * pageBytes);
    auto bytes = cast(ubyte*) block;
    foreach (page; 0 .. 4)
        bytes[page * pageBytes] = 1; // make every page present
    assert(tracker.clear());
    bool[4] dirty;
    assert(tracker.read(block, dirty[]));
    assert(dirty == [false, false, false, false], "clear_refs left a page soft-dirty");
    bytes[2 * pageBytes + 100] = 7;
    assert(tracker.read(block, dirty[]));
    assert(dirty == [false, false, true, false], "a written page is not soft-dirty, or an unwritten one is");
}
