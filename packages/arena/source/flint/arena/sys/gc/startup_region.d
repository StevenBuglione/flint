/++
A permanent start-up region (prototype, opt-in; coordinator 2026-11-25, docs/spring/phase1/gc.md).

A program's start-up builds thousands of small permanent objects: bean definitions, descriptor tables, mapping
registries. A conservative collection marks each of them on every cycle, and reaching a scattered object costs about
50 ns, against about 0.04 ns per byte for a contiguous root range (m7's census of petclinic-rest, 2026-11-25). While
the region is open, `StartupRegionGC` bump-allocates the opening thread's allocations from a few large zeroed chunks,
each registered with the collector as a root range, so the collector scans them as plain memory instead of marking
them as objects.

Rules:
- Only the thread that opened the region allocates from it, and only while it is open. Other threads, and every
  allocation after `close`, go to the collector unchanged.
- An allocation with a finalizer (`FINALIZE` or `STRUCTFINAL`) goes to the collector, so every destructor still runs
  as before.
- Region memory is never freed or reused. `free` ignores a region block, `extend` cannot grow one, and `realloc`
  copies one out to a new block. An object that start-up drops stays in the region, scanned, holding whatever it
  pointed to: retained, never reused.
- The collector does not know region blocks: `addrOf`, `query`, `sizeOf` and `getArrayUsed` report no block, so
  appending to a region array copies it to the heap, as appending to any memory outside the heap does.
- `close` shrinks each chunk's root range to the bytes allocated from it.
+/
module flint.arena.sys.gc.startup_region;

@system:

import core.gc.gcinterface : BlkInfo, GC, RangeIterator, RootIterator;
import core.internal.spinlock : SpinLock;
import core.thread.threadbase : ThreadBase;
static import core.memory;

private extern (C) GC gc_getProxy() nothrow @nogc;
private extern (C) void gc_setProxy(GC proxy) nothrow;

/// Bytes each chunk reserves; an allocation larger than a chunk gets a chunk of its own.
private enum chunkBytes = 1024 * 1024;

/// Bytes before each block: its usable size, keeping the block 16-byte aligned.
private enum header = 16;

/// Chunks the region can hold (64 MiB of start-up at the default size).
private enum maxChunks = 64;

private struct Chunk
{
    ubyte* base;
    size_t used;
    size_t size;
}

private __gshared Chunk[maxChunks] chunks;
private __gshared size_t chunkCount;
private __gshared StartupRegionGC installed;
private shared SpinLock regionLock = SpinLock(SpinLock.Contention.brief);
/// Whether this thread allocates from the region (only the opening thread, while it is open).
private bool regionThread; // thread-local by design (sys/ allowlist)
private __gshared size_t regionBytes, regionBlocks;

/// Bytes and blocks allocated from the region so far.
size_t startupRegionBytes() nothrow @nogc
{
    return regionBytes;
}

/// ditto
size_t startupRegionBlocks() nothrow @nogc
{
    return regionBlocks;
}

/// Whether `p` lies in the region's allocated memory.
bool inStartupRegion(const void* p) nothrow @nogc
{
    foreach (ref chunk; chunks[0 .. chunkCount])
        if (p >= chunk.base && p < chunk.base + chunk.used)
            return true;
    return false;
}

/// Open the region on the calling thread: put the proxy in front of the running collector. Call before the program
/// starts other threads. False if a region was opened before.
bool openStartupRegion() nothrow
{
    if (installed !is null)
        return false;
    installed = new StartupRegionGC(gc_getProxy());
    installed.copying = true;
    gc_setProxy(installed);
    installed.copying = false;
    regionThread = true;
    return true;
}

/// Close the region: from now on every allocation goes to the collector. The proxy stays installed, so region blocks
/// keep their rules. Each chunk's root range shrinks to its allocated bytes. Call on the opening thread.
void closeStartupRegion() nothrow
{
    if (installed is null || !regionThread)
        return;
    regionLock.lock();
    regionThread = false;
    foreach (ref chunk; chunks[0 .. chunkCount])
    {
        installed.inner.removeRange(chunk.base);
        if (chunk.used)
            installed.inner.addRange(chunk.base, chunk.used, null);
    }
    regionLock.unlock();
}

private extern (C) void gc_clrProxy() nothrow;

/// Remove the proxy after a closed region, for a test program whose other tests check the collector itself. Region
/// blocks stay allocated and scanned; `free` and `realloc` on them then go to the collector, which ignores foreign
/// memory.
void removeStartupRegionProxy() nothrow
{
    if (installed is null)
        return;
    closeStartupRegion();
    installed.copying = true;
    gc_clrProxy();
    installed = null;
}

/// A block of `size` bytes from the region, zeroed; null if the region is full.
private void* regionAlloc(size_t size) nothrow
{
    import core.stdc.stdlib : calloc;

    const rounded = (size + 15) & ~cast(size_t) 15;
    const need = rounded + header;
    regionLock.lock();
    scope (exit)
        regionLock.unlock();
    Chunk* chunk = chunkCount ? &chunks[chunkCount - 1] : null;
    if (chunk is null || chunk.size - chunk.used < need)
    {
        if (chunkCount == maxChunks)
            return null;
        const bytes = need > chunkBytes ? need : chunkBytes;
        auto base = cast(ubyte*) calloc(bytes, 1);
        if (base is null)
            return null;
        chunks[chunkCount++] = Chunk(base, 0, bytes);
        chunk = &chunks[chunkCount - 1];
        installed.inner.addRange(base, bytes, null);
    }
    auto block = chunk.base + chunk.used;
    chunk.used += need;
    *cast(size_t*) block = rounded;
    regionBytes += rounded;
    regionBlocks++;
    return block + header;
}

/// The usable size of a region block.
private size_t regionSize(const void* p) nothrow @nogc
{
    return *cast(const(size_t)*)(p - header);
}

private bool fromRegion(uint bits) nothrow @nogc
{
    alias Attr = core.memory.GC.BlkAttr;
    return regionThread && !(bits & (Attr.FINALIZE | Attr.STRUCTFINAL));
}

/// Forwards every call to the collector it was installed over, except the opening thread's allocations while the
/// region is open, and calls on region blocks.
final class StartupRegionGC : GC
{
    private GC inner;
    /// While druntime copies roots and ranges in `gc_setProxy`, they already live in `inner`.
    private bool copying;

    this(GC inner) nothrow @nogc
    {
        this.inner = inner;
    }

    void enable()
    {
        inner.enable();
    }

    void disable()
    {
        inner.disable();
    }

    void collect() nothrow
    {
        inner.collect();
    }

    void minimize() nothrow
    {
        inner.minimize();
    }

    uint getAttr(void* p) nothrow
    {
        return inner.getAttr(p);
    }

    uint setAttr(void* p, uint mask) nothrow
    {
        return inner.setAttr(p, mask);
    }

    uint clrAttr(void* p, uint mask) nothrow
    {
        return inner.clrAttr(p, mask);
    }

    void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        if (fromRegion(bits))
            if (auto p = regionAlloc(size))
                return p;
        return inner.malloc(size, bits, ti);
    }

    BlkInfo qalloc(size_t size, uint bits, const scope TypeInfo ti) nothrow
    {
        if (fromRegion(bits))
            if (auto p = regionAlloc(size))
                return BlkInfo(p, regionSize(p), bits);
        return inner.qalloc(size, bits, ti);
    }

    void* calloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        if (fromRegion(bits))
            if (auto p = regionAlloc(size))
                return p; // region chunks are zeroed and never reused
        return inner.calloc(size, bits, ti);
    }

    void* realloc(void* p, size_t size, uint bits, const TypeInfo ti) nothrow
    {
        import core.stdc.string : memcpy;

        if (p is null || !inStartupRegion(p))
            return inner.realloc(p, size, bits, ti);
        if (size == 0)
            return null; // a region block is never freed
        auto moved = malloc(size, bits, ti);
        if (moved !is null)
        {
            const old = regionSize(p);
            memcpy(moved, p, old < size ? old : size);
        }
        return moved;
    }

    size_t extend(void* p, size_t minsize, size_t maxsize, const TypeInfo ti) nothrow
    {
        return inStartupRegion(p) ? 0 : inner.extend(p, minsize, maxsize, ti);
    }

    size_t reserve(size_t size) nothrow
    {
        return inner.reserve(size);
    }

    void free(void* p) nothrow @nogc
    {
        if (!inStartupRegion(p))
            inner.free(p);
    }

    void* addrOf(void* p) nothrow @nogc
    {
        return inner.addrOf(p);
    }

    size_t sizeOf(void* p) nothrow @nogc
    {
        return inner.sizeOf(p);
    }

    BlkInfo query(void* p) nothrow
    {
        return inner.query(p);
    }

    // SAFETY: Forwards to the inner collector's @safe statistics; no pointer is involved.
    core.memory.GC.Stats stats() @trusted nothrow @nogc
    {
        return inner.stats();
    }

    // SAFETY: Forwards to the inner collector's @safe profile counters; no pointer is involved.
    core.memory.GC.ProfileStats profileStats() @trusted nothrow @nogc
    {
        return inner.profileStats();
    }

    void addRoot(void* p) nothrow @nogc
    {
        if (!copying)
            inner.addRoot(p);
    }

    void removeRoot(void* p) nothrow @nogc
    {
        if (!copying)
            inner.removeRoot(p);
    }

    @property RootIterator rootIter() @nogc
    {
        return inner.rootIter;
    }

    void addRange(void* p, size_t sz, const TypeInfo ti) nothrow @nogc
    {
        if (!copying)
            inner.addRange(p, sz, ti);
    }

    void removeRange(void* p) nothrow @nogc
    {
        if (!copying)
            inner.removeRange(p);
    }

    @property RangeIterator rangeIter() @nogc
    {
        return inner.rangeIter;
    }

    void runFinalizers(const scope void[] segment) nothrow
    {
        inner.runFinalizers(segment);
    }

    // SAFETY: Forwards to the inner collector's @safe query; no pointer is involved.
    @trusted bool inFinalizer() nothrow @nogc
    {
        return inner.inFinalizer();
    }

    ulong allocatedInCurrentThread() nothrow
    {
        return inner.allocatedInCurrentThread();
    }

    void[] getArrayUsed(void* ptr, bool atomic = false) nothrow
    {
        return inner.getArrayUsed(ptr, atomic);
    }

    // SAFETY: Forwards the caller's slice to the inner collector's @safe operation unchanged.
    @trusted bool expandArrayUsed(void[] slice, size_t newUsed, bool atomic = false) nothrow
    {
        return inner.expandArrayUsed(slice, newUsed, atomic);
    }

    // SAFETY: Forwards the caller's slice to the inner collector's @safe operation unchanged.
    @trusted size_t reserveArrayCapacity(void[] slice, size_t request, bool atomic = false) nothrow
    {
        return inner.reserveArrayCapacity(slice, request, atomic);
    }

    bool shrinkArrayUsed(void[] slice, size_t existingUsed, bool atomic = false) nothrow
    {
        return inner.shrinkArrayUsed(slice, existingUsed, atomic);
    }

    void initThread(ThreadBase thread) nothrow @nogc
    {
        inner.initThread(thread);
    }

    void cleanupThread(ThreadBase thread) nothrow @nogc
    {
        inner.cleanupThread(thread);
    }
}
