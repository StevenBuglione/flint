/++
A counting proxy over the running collector, for the per-request allocation gate (policy/request-allocations.json,
owner decision 9a9aefa0).

`install` puts a `CountingGC` in front of whatever collector druntime runs (its default conservative collector in
shipped programs), through druntime's own `gc_setProxy`. Every call is forwarded unchanged; on the way, each thread
counts its allocations, and the bytes the collector itself counts for them: the difference of the collector's
`allocatedInCurrentThread` around each forwarded call, so the bytes equal druntime's by construction. Threads register
on their first allocation and leave in `cleanupThread`, so a test client can read what a server's threads allocated.

With call-site recording on, each counted allocation also keeps its return addresses, which `topSites` symbolizes.
This is test support: nothing installs it unless a test does.
+/
module flint.arena.sys.gc.counting;

@system:

import core.gc.gcinterface : BlkInfo, GC, RangeIterator, RootIterator;
import core.internal.spinlock : SpinLock;
import core.thread.threadbase : ThreadBase;
static import core.memory;

private extern (C) GC gc_getProxy() nothrow @nogc;
private extern (C) void gc_setProxy(GC proxy) nothrow;
private extern (C) void gc_clrProxy() nothrow;

/// Return addresses kept per recorded allocation.
private enum siteDepth = 8;

/// Recorded allocations kept per thread.
private enum siteCapacity = 4_096;

/// One thread's totals, linked into the registry under `registryLock`.
private struct ThreadCounts
{
    shared ulong count;
    shared ulong bytes;
    ThreadCounts* next;
    ThreadBase owner;
    bool registered;
    size_t recorded;
    /// Return addresses of recorded allocations: `siteCapacity` rows, malloc'd on the first recording; the last slot
    /// of a row holds the allocation's bytes.
    void*[siteDepth + 1]* sites;
}

private ThreadCounts threadCounts; // thread-local by design (policy/safety-policy.json)
private __gshared ThreadCounts* registry;
private shared SpinLock registryLock = SpinLock(SpinLock.Contention.brief);
private __gshared CountingGC installed;
private shared bool recordSites;

/// Forwards every call to the collector it was installed over, counting allocations per thread.
final class CountingGC : GC
{
    private GC inner;
    /// While druntime copies roots and ranges in `gc_setProxy`/`gc_clrProxy`, they already live in `inner`.
    private bool copying;

    this(GC inner) nothrow @nogc
    {
        this.inner = inner;
    }

    private void counted(size_t before, bool newBlock) nothrow
    {
        import core.atomic : MemoryOrder, atomicLoad, atomicStore;

        if (!threadCounts.registered)
            register();
        const added = inner.allocatedInCurrentThread() - before;
        atomicStore!(MemoryOrder.raw)(threadCounts.bytes, atomicLoad!(MemoryOrder.raw)(threadCounts.bytes) + added);
        if (!newBlock)
            return;
        atomicStore!(MemoryOrder.raw)(threadCounts.count, atomicLoad!(MemoryOrder.raw)(threadCounts.count) + 1);
        if (atomicLoad!(MemoryOrder.raw)(recordSites) && threadCounts.recorded < siteCapacity)
            record(added);
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
        const before = inner.allocatedInCurrentThread();
        auto p = inner.malloc(size, bits, ti);
        counted(before, p !is null);
        return p;
    }

    BlkInfo qalloc(size_t size, uint bits, const scope TypeInfo ti) nothrow
    {
        const before = inner.allocatedInCurrentThread();
        auto info = inner.qalloc(size, bits, ti);
        counted(before, info.base !is null);
        return info;
    }

    void* calloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        const before = inner.allocatedInCurrentThread();
        auto p = inner.calloc(size, bits, ti);
        counted(before, p !is null);
        return p;
    }

    void* realloc(void* p, size_t size, uint bits, const TypeInfo ti) nothrow
    {
        const before = inner.allocatedInCurrentThread();
        auto moved = inner.realloc(p, size, bits, ti);
        counted(before, moved !is null && moved !is p);
        return moved;
    }

    size_t extend(void* p, size_t minsize, size_t maxsize, const TypeInfo ti) nothrow
    {
        const before = inner.allocatedInCurrentThread();
        const extended = inner.extend(p, minsize, maxsize, ti);
        counted(before, false);
        return extended;
    }

    size_t reserve(size_t size) nothrow
    {
        return inner.reserve(size);
    }

    void free(void* p) nothrow @nogc
    {
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
        const before = inner.allocatedInCurrentThread();
        const expanded = inner.expandArrayUsed(slice, newUsed, atomic);
        counted(before, false);
        return expanded;
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
        unregister(thread);
        inner.cleanupThread(thread);
    }
}

/// Link this thread's totals into the registry.
private void register() nothrow @nogc
{
    registryLock.lock();
    scope (exit)
        registryLock.unlock();
    threadCounts.owner = ThreadBase.getThis();
    threadCounts.next = registry;
    registry = &threadCounts;
    threadCounts.registered = true;
}

/// Unlink the totals `owner` registered, before its TLS goes away.
private void unregister(ThreadBase owner) nothrow @nogc
{
    registryLock.lock();
    scope (exit)
        registryLock.unlock();
    for (auto link = &registry; *link !is null; link = &(*link).next)
    {
        if ((*link).owner is owner)
        {
            auto counts = *link;
            *link = counts.next;
            counts.registered = false;
            counts.next = null;
            releaseSites(*counts);
            return;
        }
    }
}

/// Free a record's call-site buffer.
private void releaseSites(ref ThreadCounts counts) nothrow @nogc
{
    import core.stdc.stdlib : cfree = free;

    cfree(counts.sites);
    counts.sites = null;
    counts.recorded = 0;
}

/// Keep the return addresses of the allocation being counted, past `record` and `counted` (Linux only).
private void record(size_t bytes) nothrow @nogc
{
    version (linux)
    {
        import core.stdc.stdlib : cmalloc = malloc;
        import core.sys.linux.execinfo : backtrace;

        if (threadCounts.sites is null)
        {
            threadCounts.sites = cast(void*[siteDepth + 1]*) cmalloc(siteCapacity * (void*[siteDepth + 1]).sizeof);
            if (threadCounts.sites is null)
                return;
        }
        void*[siteDepth + 2] raw;
        const found = backtrace(raw.ptr, cast(int) raw.length);
        auto frames = threadCounts.sites[threadCounts.recorded++][];
        frames[] = null;
        foreach (i; 0 .. siteDepth)
            if (i + 2 < found)
                frames[i] = raw[i + 2];
        frames[siteDepth] = cast(void*) bytes;
    }
}

/// Put the counting proxy in front of the running collector; false if it is installed already. Call it before
/// starting the threads to be counted.
// SAFETY: druntime's gc_setProxy swaps its instance pointer; the proxy forwards every call to the collector it saved,
// and ignores the roots and ranges druntime copies into it, which that collector already holds.
@trusted bool install() nothrow
{
    if (installed !is null)
        return false;
    auto inner = gc_getProxy();
    installed = new CountingGC(inner); // allocated by the inner collector, before the switch
    installed.copying = true;
    gc_setProxy(installed);
    installed.copying = false;
    return true;
}

/// Remove the counting proxy.
// SAFETY: gc_clrProxy restores druntime's own instance; the proxy ignores the root and range removals it replays.
@trusted void uninstall() nothrow
{
    if (installed is null)
        return;
    installed.copying = true;
    gc_clrProxy();
    installed = null;
    registryLock.lock();
    for (auto counts = registry; counts !is null; counts = counts.next)
        releaseSites(*counts);
    registryLock.unlock();
}

/// Whether the counting proxy is installed.
// SAFETY: Reads one __gshared reference.
@trusted bool isInstalled() nothrow @nogc
{
    return installed !is null;
}

/// The allocations and bytes of every registered thread but the caller.
// SAFETY: Walks the registry under its lock; each record stays linked until its thread's cleanupThread unlinks it.
@trusted void otherThreads(out ulong count, out ulong bytes) nothrow @nogc
{
    import core.atomic : MemoryOrder, atomicLoad;

    registryLock.lock();
    scope (exit)
        registryLock.unlock();
    for (auto counts = registry; counts !is null; counts = counts.next)
    {
        if (counts is &threadCounts)
            continue;
        count += atomicLoad!(MemoryOrder.raw)(counts.count);
        bytes += atomicLoad!(MemoryOrder.raw)(counts.bytes);
    }
}

/// The calling thread's allocations and bytes.
// SAFETY: Reads the calling thread's own TLS record.
@trusted void thisThread(out ulong count, out ulong bytes) nothrow @nogc
{
    import core.atomic : MemoryOrder, atomicLoad;

    count = atomicLoad!(MemoryOrder.raw)(threadCounts.count);
    bytes = atomicLoad!(MemoryOrder.raw)(threadCounts.bytes);
}

/// Turn call-site recording on (clearing what every thread recorded) or off. Turn it off before `topSites`.
// SAFETY: Resets each linked record's count under the registry lock; the site buffers stay owned by their records.
@trusted void recordCallSites(bool on) nothrow @nogc
{
    import core.atomic : atomicStore;

    if (on)
    {
        registryLock.lock();
        for (auto counts = registry; counts !is null; counts = counts.next)
            counts.recorded = 0;
        registryLock.unlock();
    }
    atomicStore(recordSites, on);
}

/// The `limit` most frequent first frames outside druntime and this module among the allocations other threads
/// recorded, as "count  function" lines.
// SAFETY: Copies the recorded return addresses under the registry lock, then symbolizes copies only.
@trusted string[] topSites(size_t limit, bool includeCaller = false)
{
    size_t[2][string] tally;
    version (linux)
        tallySites(tally, includeCaller);
    string[] lines;
    foreach (name, counts; tally)
        lines ~= rightAligned(counts[0]) ~ rightAligned(counts[1], 11) ~ " B  " ~ name;
    sortDescending(lines);
    return lines.length > limit ? lines[0 .. limit] : lines;
}

/// The same tally ordered by bytes.
// SAFETY: As topSites: symbolizes copies of the recorded addresses.
@trusted string[] topSitesByBytes(size_t limit, bool includeCaller = false)
{
    size_t[2][string] tally;
    version (linux)
        tallySites(tally, includeCaller);
    string[] lines;
    foreach (name, counts; tally)
        lines ~= rightAligned(counts[1], 11) ~ " B" ~ rightAligned(counts[0]) ~ "  " ~ name;
    sortDescending(lines);
    return lines.length > limit ? lines[0 .. limit] : lines;
}

version (linux) private void tallySites(ref size_t[2][string] tally, bool includeCaller)
{
    if (!threadCounts.registered)
        register(); // the helpers allocate; a first registration under the lock would wait on itself
    auto rows = recordedRows(includeCaller);
    const names = symbolize(executableOffsets(rows));
    foreach (ref frames; rows)
        foreach (frame; frames[0 .. siteDepth])
        {
            const name = names.get(frame, null);
            if (frame is null || runtimeFrame(name))
                continue;
            auto counts = name in tally;
            if (counts is null)
            {
                tally[name] = [0, 0];
                counts = name in tally;
            }
            (*counts)[0] += 1;
            (*counts)[1] += cast(size_t) frames[siteDepth];
            break;
        }
}

/// Every other thread's recorded frames, copied out under the registry lock.
version (linux) private void*[siteDepth + 1][] recordedRows(bool includeCaller)
{
    void*[siteDepth + 1][] rows;
    registryLock.lock();
    scope (exit)
        registryLock.unlock();
    for (auto counts = registry; counts !is null; counts = counts.next)
        if ((includeCaller || counts !is &threadCounts) && counts.sites !is null)
            rows ~= counts.sites[0 .. counts.recorded];
    return rows;
}

/// The address of each distinct frame in the executable itself, as addr2line reads it: relative to the load base of
/// a position-independent executable, absolute in a fixed one, and one byte back, on the call rather than the return.
/// A shared library's frames are left out: their offsets are relative to their own base.
version (linux) private size_t[const(void)* ] executableOffsets(const(void*[siteDepth + 1])[] rows)
{
    import core.sys.linux.dlfcn : Dl_info, dladdr;

    Dl_info self;
    if (dladdr(cast(void*)&register, &self) == 0 || self.dli_fbase is null)
        return null;
    const base = positionIndependent() ? cast(size_t) self.dli_fbase : 0;
    size_t[const(void)* ] offsets;
    foreach (ref frames; rows)
        foreach (frame; frames[0 .. siteDepth])
        {
            Dl_info info;
            if (frame is null || frame in offsets || dladdr(frame, &info) == 0 || info.dli_fbase !is self.dli_fbase)
                continue;
            offsets[frame] = cast(size_t) frame - base - 1;
        }
    return offsets;
}

/// The qualified function name at each address, from one addr2line run over the executable's symbols and DWARF.
/// That works whether or not the link exported dynamic symbols: DMD's does, LDC's does not, so backtrace_symbols
/// cannot name LDC frames.
version (linux) private string[const(void)* ] symbolize(size_t[const(void)* ] offsets)
{
    import core.demangle : demangle;
    import std.conv : to;
    import std.file : thisExePath;
    import std.process : execute;
    import std.string : lineSplitter, strip;

    if (offsets.length == 0)
        return null;
    // Not /proc/self/exe: in the child, that names addr2line itself.
    string[] arguments = ["addr2line", "-f", "-e", thisExePath()];
    const(void)*[] order;
    foreach (frame, offset; offsets)
    {
        order ~= frame;
        arguments ~= "0x" ~ offset.to!string(16);
    }
    const result = execute(arguments);
    if (result.status != 0)
        return null;
    string[const(void)* ] names;
    size_t line;
    foreach (text; result.output.lineSplitter) // two lines per address: the function, then file:line
    {
        if (line % 2 == 0 && line / 2 < order.length)
            names[order[line / 2]] = qualifiedName(demangle(text.strip).idup);
        ++line;
    }
    return names;
}

/// The qualified function name of a demangled symbol, without its attributes, return type and parameters: the first
/// top-level word whose text before its parameter list is qualified (`a.b.f(...)`), so a return type such as
/// `immutable(char)[]` is skipped.
private string qualifiedName(string symbol) @safe pure nothrow @nogc
{
    size_t start;
    int depth;
    foreach (i; 0 .. symbol.length + 1)
    {
        const c = i < symbol.length ? symbol[i] : ' ';
        if (c == '(')
            ++depth;
        else if (c == ')')
            --depth;
        else if (c == ' ' && depth == 0)
        {
            const name = functionPart(symbol[start .. i]);
            if (name.length)
                return name;
            start = i + 1;
        }
    }
    return symbol;
}

/// `word` up to its parameter list when that part is a qualified name, else null.
private string functionPart(string word) @safe pure nothrow @nogc
{
    foreach (i, c; word)
        if (c == '(' && (i == 0 || word[i - 1] != '!'))
        {
            foreach (d; word[0 .. i])
                if (d == '.')
                    return word[0 .. i];
            return null;
        }
    return null;
}

/// Whether the running executable is position-independent (ELF type ET_DYN rather than ET_EXEC).
version (linux) private bool positionIndependent()
{
    import std.file : read;

    const header = cast(const(ubyte)[]) read("/proc/self/exe", 18);
    return header.length == 18 && header[16] == 3;
}

private bool runtimeFrame(const(char)[] name) nothrow @nogc
{
    if (name == "??")
        return true; // unresolved
    foreach (prefix; [
        "core.", "object.", "rt.", "_d_", "gc_", "flint.arena.sys.gc.", "std.array.", "std.conv."
    ])
        if (name.length >= prefix.length && name[0 .. prefix.length] == prefix)
            return true;
    return name.length == 0;
}

private ptrdiff_t indexOf(const(char)[] text, char c) nothrow @nogc
{
    foreach (i, d; text)
        if (d == c)
            return i;
    return -1;
}

private string rightAligned(size_t value, size_t width = 6)
{
    import std.conv : to;

    auto text = value.to!string;
    while (text.length < width)
        text = " " ~ text;
    return text;
}

private void sortDescending(string[] lines)
{
    foreach (i; 1 .. lines.length)
        for (auto j = i; j > 0 && lines[j - 1] < lines[j]; --j)
        {
            auto swapped = lines[j];
            lines[j] = lines[j - 1];
            lines[j - 1] = swapped;
        }
}

@("call-site names drop attributes, return types and parameters")
@safe unittest
{
    assert(qualifiedName("nothrow void* flint.arena.sys.gc.counting.CountingGC.malloc(ulong, uint, const(TypeInfo))")
            == "flint.arena.sys.gc.counting.CountingGC.malloc");
    assert(qualifiedName(
            "immutable(char)[] flint.java.lang.String.format(immutable(char)[], Any[])") == "flint.java.lang.String.format");
    assert(qualifiedName("const(flint.http.MediaType)[] flint.web.f!(int).g(int)") == "flint.web.f!(int).g");
    assert(qualifiedName("_d_newarrayT") == "_d_newarrayT");
}
