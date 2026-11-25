/// Linux slice 0 probe. Define FlintSoftDirtyProbe to build the standalone entry point.
module softdirty_probe;

@safe:
version (linux)  : import core.stdc.errno : errno, EINVAL, ENOTTY, EINTR;
import core.sys.posix.fcntl : open, O_CLOEXEC, O_RDONLY, O_WRONLY;
import core.sys.posix.sys.ioctl : ioctl, _IOWR;
import core.sys.posix.sys.mman : mmap, mprotect, munmap, MAP_ANON, MAP_PRIVATE, MAP_FIXED,
    MAP_FAILED, PROT_NONE, PROT_READ, PROT_WRITE;
import core.sys.posix.unistd : sysconf, _SC_PAGESIZE, close, pread, pwrite, pipe, read, write;
import core.time : MonoTime;
import std.exception : enforce;

private enum rw = PROT_READ | PROT_WRITE;
private enum softDirty = 1UL << 55;
private enum pageIsSoftDirty = 1UL << 7;

// linux/fs.h UAPI. Fixed-width fields even on ILP32.
private struct PageRegion
{
    ulong start, end, categories;
}

private struct ScanArg
{
    ulong size = ScanArg.sizeof;
    ulong flags, start, end, walkEnd, vec, vecLen, maxPages, inverted, categoryMask, anyMask, returnMask;
}

static assert(ScanArg.sizeof == 96 && PageRegion.sizeof == 24);

private struct Proc
{
    int pagemap, clearRefs;
    size_t pageSize;

    static Proc acquire() @system
    {
        const page = sysconf(_SC_PAGESIZE);
        enforce(page > 0, "sysconf(_SC_PAGESIZE) failed");
        const pm = open("/proc/self/pagemap", O_RDONLY | O_CLOEXEC);
        enforce(pm >= 0, "open pagemap failed");
        scope (failure)
            close(pm);
        const cr = open("/proc/self/clear_refs", O_WRONLY | O_CLOEXEC);
        enforce(cr >= 0, "open clear_refs failed");
        return Proc(pm, cr, cast(size_t) page);
    }

    void release() @system
    {
        close(clearRefs);
        close(pagemap);
    }

    void clear() @system
    {
        enforce(pwrite(clearRefs, "4".ptr, 1, 0) == 1, "clear_refs write failed");
    }

    void entries(const(void)* start, ulong[] dst) @system
    {
        // Linux pagemap ABI. Unlike bdwgc os_dep.c:pagemap_buffered_read this measures
        // one exact positional read. The probe owns the entire destination buffer.
        const offset = cast(long)((cast(size_t) start / pageSize) * ulong.sizeof);
        const bytes = dst.length * ulong.sizeof;
        enforce(pread(pagemap, dst.ptr, bytes, offset) == cast(long) bytes, "short pagemap read");
    }

    bool dirty(const(void)* addr) @system
    {
        ulong[1] entry;
        entries(addr, entry[]);
        return (entry[0] & softDirty) != 0;
    }

    /// Returns -1 only for kernels without the ioctl or its soft-dirty category.
    long scan(const(void)* addr, size_t bytes) @system
    {
        PageRegion[64] regions = void;
        ScanArg a;
        a.start = cast(size_t) addr;
        a.end = a.start + bytes;
        a.vec = cast(size_t) regions.ptr;
        a.vecLen = regions.length;
        a.categoryMask = a.returnMask = pageIsSoftDirty;
        enum request = cast(uint) _IOWR!ScanArg('f', 16);
        long pages;
        while (a.start < a.end)
        {
            const n = ioctl(pagemap, request, &a);
            if (n < 0 && errno == EINTR)
                continue;
            if (n < 0 && (errno == ENOTTY || errno == EINVAL))
                return -1;
            enforce(n >= 0 && n <= regions.length, "PAGEMAP_SCAN failed");
            enforce(a.start < a.walkEnd && a.walkEnd <= a.end, "PAGEMAP_SCAN made invalid progress");
            foreach (region; regions[0 .. n])
            {
                enforce(region.categories == pageIsSoftDirty && region.start >= a.start
                        && region.start < region.end && region.end <= a.walkEnd, "invalid PAGEMAP_SCAN range");
                pages += (region.end - region.start) / pageSize;
            }
            a.start = a.walkEnd;
        }
        return pages;
    }
}

private ubyte* mapping(size_t bytes, int prot) @system
{
    auto addr = mmap(null, bytes, prot, MAP_PRIVATE | MAP_ANON, -1, 0);
    enforce(addr != MAP_FAILED, "mmap failed");
    return cast(ubyte*) addr;
}

private void selfTest(ref Proc proc) @system
{
    const p = proc.pageSize;
    // Reserve guard pages around two adjacent anonymous mappings. MAP_FIXED replaces only
    // pages owned by this reservation. Leave the first page unfaulted to observe the VMA bit.
    auto guard = mapping(4 * p, PROT_NONE);
    scope (exit)
        munmap(guard, 4 * p);
    auto first = guard + p;
    enforce(mmap(first, p, rw, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == first);
    proc.clear();
    enforce(!proc.dirty(first), "first mapping did not clear");
    enforce(mmap(first + p, p, rw, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == first + p);
    enforce(proc.dirty(first), "C5: adjacent mmap did not dirty the first region");

    // As in bdwgc os_dep.c:detect_soft_dirty_supported, check a real transition on a
    // resident page. Use the kernel pipe write to test the transition we care about here.
    int[2] fds;
    enforce(pipe(fds) == 0, "pipe failed");
    scope (exit)
    {
        close(fds[0]);
        close(fds[1]);
    }
    enforce(write(fds[1], "X".ptr, 1) == 1);
    first[0] = 1;
    enforce(proc.dirty(first), "user write did not set soft-dirty");
    proc.clear();
    enforce(!proc.dirty(first), "resident page did not clear");
    enforce(read(fds[0], first, 1) == 1 && first[0] == 'X');
    enforce(proc.dirty(first), "pipe read did not set soft-dirty");
}

private struct Sample
{
    size_t pages, extraVmas, totalVmas, dirtyPages;
    long preadNs, enumerateNs, scanNs, clearNs;
}

private size_t countVmas() @system
{
    import core.stdc.stdio : fopen, fclose, fgetc, ferror, EOF;

    auto maps = fopen("/proc/self/maps", "r");
    enforce(maps !is null);
    scope (exit)
        fclose(maps);
    size_t lines;
    for (int c; (c = fgetc(maps)) != EOF;)
        lines += c == '\n';
    enforce(ferror(maps) == 0 && lines > 0, "reading /proc/self/maps failed");
    return lines;
}

private Sample measure(ref Proc proc, size_t pages, size_t extraVmas) @system
{
    // Alternating readable/PROT_NONE pages create 2,200 separate VMAs, avoiding anonymous coalescing.
    const vmaBytes = extraVmas * proc.pageSize;
    auto vmas = extraVmas ? mapping(vmaBytes, PROT_NONE) : null;
    scope (exit)
        if (vmas)
            munmap(vmas, vmaBytes);
    foreach (i; 0 .. extraVmas / 2)
        enforce(mprotect(vmas + 2 * i * proc.pageSize, proc.pageSize, PROT_READ) == 0);

    const bytes = pages * proc.pageSize;
    auto data = mapping(bytes, rw);
    scope (exit)
        munmap(data, bytes);
    // Keep dirty granularity at one base page even on hosts configured for transparent huge pages.
    import core.sys.linux.sys.mman : madvise, MADV_NOHUGEPAGE;

    enforce(madvise(data, bytes, MADV_NOHUGEPAGE) == 0);
    auto entries = new ulong[pages];
    foreach (i; 0 .. pages)
    {
        data[i * proc.pageSize] = 1;
        entries[i] = 1; // fault in the output buffer before timing the read
    }

    Sample s;
    s.pages = pages;
    s.extraVmas = extraVmas;
    s.totalVmas = countVmas();
    auto start = MonoTime.currTime;
    proc.clear();
    s.clearNs = (MonoTime.currTime - start).total!"nsecs";
    for (size_t i = 0; i < pages; i += 8)
        data[i * proc.pageSize] = 2;
    start = MonoTime.currTime;
    proc.entries(data, entries);
    s.preadNs = (MonoTime.currTime - start).total!"nsecs";
    foreach (entry; entries)
        s.dirtyPages += (entry & softDirty) != 0;
    s.enumerateNs = (MonoTime.currTime - start).total!"nsecs";
    enforce(s.dirtyPages == (pages + 7) / 8, "unexpected pagemap dirty count");
    start = MonoTime.currTime;
    const scanned = proc.scan(data, bytes);
    s.scanNs = (MonoTime.currTime - start).total!"nsecs";
    if (scanned < 0)
        s.scanNs = -1;
    else
        enforce(scanned == s.dirtyPages, "PAGEMAP_SCAN and pread disagree");
    return s;
}

@system unittest
{
    auto proc = Proc.acquire();
    scope (exit)
        proc.release();
    selfTest(proc);
    // More dirty ranges than fit one ioctl result; must advance walk_end.
    const sample = measure(proc, 1_500, 0);
    assert(sample.dirtyPages == 188);
    const fragmented = measure(proc, 1_500, 2_200);
    assert(fragmented.dirtyPages == sample.dirtyPages);
    // An outside edge of the reservation may merge with its neighbour.
    assert(fragmented.totalVmas >= sample.totalVmas + 2_198);

    // /dev/null rejects PAGEMAP_SCAN with ENOTTY even on a supporting kernel.
    const fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
    enforce(fd >= 0);
    scope (exit)
        close(fd);
    auto unsupported = Proc(fd, -1, proc.pageSize);
    assert(unsupported.scan(null, proc.pageSize) == -1);
}

version (FlintSoftDirtyProbe) @system int main(string[] args)
{
    import std.stdio : writefln, writeln;
    import std.json : JSONValue;

    auto proc = Proc.acquire();
    scope (exit)
        proc.release();
    selfTest(proc);
    writeln("C5 adjacent mapping: dirty; pipe read into clean page: dirty");
    enforce(args.length == 1 || (args.length == 2 && args[1] == "--self-test"), "usage: softdirty_probe [--self-test]");
    const checkOnly = args.length == 2;
    JSONValue[] rows;
    enum MiB = 1_024 * 1_024;
    foreach (vmas; [0, 2_200])
        foreach (pages; [
            2 * MiB / proc.pageSize, 1_500, 10 * MiB / proc.pageSize, 20 * MiB / proc.pageSize
    ])
        {
            if (checkOnly && pages != 1_500)
                continue;
            auto s = measure(proc, pages, vmas);
            JSONValue row;
            row["pages"] = s.pages;
            row["extra_vmas"] = s.extraVmas;
            row["total_vmas"] = s.totalVmas;
            row["dirty_pages"] = s.dirtyPages;
            row["pread_ns"] = s.preadNs;
            row["enumerate_ns"] = s.enumerateNs;
            row["scan_supported"] = s.scanNs >= 0;
            if (s.scanNs >= 0)
                row["scan_ns"] = s.scanNs;
            row["clear_ns"] = s.clearNs;
            rows ~= row;
            writefln("%s pages +%s VMAs: pread %s ns, enumeration %s ns, PAGEMAP_SCAN %s, clear_refs %s ns", pages,
                    vmas, s.preadNs, s.enumerateNs, s.scanNs < 0
                    ? "unsupported" : row["scan_ns"].toString ~ " ns", s.clearNs);
        }
    JSONValue result;
    result["page_bytes"] = proc.pageSize;
    result["c5"] = true;
    result["pipe_read"] = true;
    result["samples"] = rows;
    writeln(result.toString);
    return 0;
}
