/++
Applies the static-data map flint build appends to an executable (flint_tool.support.gcmap): after the RELRO trim
(flint.arena.sys.gc.data_roots), the writable segment's registered root range is replaced by the parts that can hold
a pointer into the GC heap. On petclinic-rest that is about 18 of 484 KiB; the rest is class metadata, `__init`
images and ModuleInfo (docs/spring/phase1/gc.md, section 3c).

Three safety layers stand behind it:
$(UL
    $(LI the map is validated at startup against the loaded executable (its writable segment, its build-id, and the
        range druntime registered); anything missing or mismatched leaves the whole range scanned;)
    $(LI `FLINT_GC_STATIC_TRIM=0` turns trimming off, `=provable` keeps class metadata scanned;)
    $(LI an audit mode (debug and test profiles, `flint test`, or `FLINT_GC_STATIC_VERIFY=1`) keeps everything
        scanned and checks, after each collection, that no ClassInfo monitor and no byte the map drops points into
        the GC heap. A violation aborts with the class's name. The typed build gate (FLINT-E0xxx) rejects the only
        way to break the rule in source: giving class metadata a GC-allocated monitor.)
)
+/
module flint.arena.sys.gc.static_map;

import core.gc.gcinterface : GC, Range;

@safe:

/// The trailer's magic; it must match flint_tool.support.gcmap.
enum ubyte[8] mapMagic = ['F', 'L', 'G', 'C', 'M', 'A', 'P', '1'];
/// The trailer's size in bytes.
enum size_t trailerBytes = 64;
/// Trailer flag: audit the trimmed data instead of trimming it.
enum uint auditFlag = 1;
/// A map larger than this is not one flint wrote.
private enum ulong maxBlobBytes = 16 << 20;

/// A half-open address interval.
struct Span
{
    ulong begin;
    ulong end;
}

/// The trailer at the end of an executable that carries a map.
struct Trailer
{
    ulong blobBytes;
    ulong segmentAddress, segmentSize;
    ulong regionBegin, regionEnd;
    ulong buildId;
    uint flags;
    uint checksum;
}

/// How much to trim, from `FLINT_GC_STATIC_TRIM`.
enum TrimMode
{
    /// Drop class metadata, init images and ModuleInfo (the default).
    full,
    /// Drop only what holds no monitor: init images, ModuleInfo, padding.
    provable,
    /// Scan the whole segment, as without a map.
    off,
}

/// What happened at startup.
enum MapState
{
    /// No map: the executable was not built by flint build, or was stripped.
    absent,
    /// A map that does not belong to this executable, or is damaged: the whole range stays scanned.
    mismatched,
    /// `FLINT_GC_STATIC_TRIM=0`.
    disabled,
    /// Audit mode: the map was validated, everything stays scanned, and a watcher checks the dropped bytes.
    audited,
    /// The keep list replaced the registered range.
    applied,
}

/// The mode the environment value `value` asks for.
TrimMode trimMode(scope const(char)[] value) pure nothrow @nogc
{
    if (value == "0" || value == "off" || value == "false")
        return TrimMode.off;
    return value == "provable" ? TrimMode.provable : TrimMode.full;
}

/// The trailer in the last `trailerBytes` of a file, if `bytes` is one.
bool parseTrailer(scope const(ubyte)[] bytes, out Trailer trailer) pure nothrow @nogc
{
    if (bytes.length != trailerBytes || bytes[0 .. 8] != mapMagic[])
        return false;
    trailer.blobBytes = u64(bytes, 8);
    trailer.segmentAddress = u64(bytes, 16);
    trailer.segmentSize = u64(bytes, 24);
    trailer.regionBegin = u64(bytes, 32);
    trailer.regionEnd = u64(bytes, 40);
    trailer.buildId = u64(bytes, 48);
    trailer.flags = u32(bytes, 56);
    trailer.checksum = u32(bytes, 60);
    return trailer.blobBytes >= 8 && trailer.blobBytes <= maxBlobBytes && trailer.regionBegin < trailer.regionEnd;
}

/// FNV-1a over the blob and the trailer before its checksum field, as flint build computes it.
uint checksum(scope const(ubyte)[] blob, scope const(ubyte)[] trailer) pure nothrow @nogc
{
    uint hash = 2_166_136_261;
    foreach (b; blob)
        hash = (hash ^ b) * 16_777_619;
    foreach (b; trailer[0 .. trailerBytes - 4])
        hash = (hash ^ b) * 16_777_619;
    return hash;
}

/// The keep list `mode` selects from `blob`, checked to be sorted, disjoint and inside the region; `false` when the
/// blob is damaged. The spans are written to `into`, which must hold the list.
bool keepList(scope const(ubyte)[] blob, const ref Trailer trailer, TrimMode mode, scope Span[] into, out size_t count) pure nothrow @nogc
{
    const provable = u32(blob, 0), full = u32(blob, 4);
    if (8 + (cast(ulong) provable + full) * 16 != blob.length)
        return false;
    const first = mode == TrimMode.provable ? 0 : provable;
    count = mode == TrimMode.provable ? provable : full;
    if (count > into.length)
        return false;
    ulong previous = trailer.regionBegin;
    foreach (i; 0 .. count)
    {
        const at = 8 + (first + i) * 16;
        const span = Span(u64(blob, at), u64(blob, at + 8));
        // A keep range that starts or ends mid-word would hide pointers from the collector: refuse the map.
        const misaligned = span.begin % 8 != 0 || (span.end % 8 != 0 && span.end != trailer.regionEnd);
        if (misaligned || span.begin < previous || span.end <= span.begin || span.end > trailer.regionEnd)
            return false;
        into[i] = span;
        previous = span.end;
    }
    return true;
}

/// The most keep spans a map may carry (a few dozen in practice).
private enum maxSpans = 4096;

/// The outcome of startup, for tests and diagnostics.
private __gshared MapState state;
private __gshared ulong droppedBytes;

// SAFETY: Written once by applyStaticMap from a module constructor, before other threads exist.
@trusted MapState staticMapState() nothrow @nogc
{
    return state;
}

// SAFETY: As staticMapState.
@trusted ulong staticTrimmedBytes() nothrow @nogc
{
    return droppedBytes;
}

/// The loaded main executable: its load bias, writable segment and build-id prefix.
private struct Executable
{
    ulong bias;
    Span segment;
    ulong buildId;
    Span image;
    bool found;
}

version (linux)
{
    import core.sys.linux.link : dl_iterate_phdr, dl_phdr_info;

    // SAFETY: The loader passes a valid info whose program headers and PT_NOTE contents stay mapped for the
    // executable's lifetime; `data` is the caller's live Executable.
    private extern (C) int describeMain(dl_phdr_info* info, size_t, void* data) @trusted nothrow @nogc
    {
        auto main = cast(Executable*) data;
        enum uint ptLoad = 1, ptNote = 4, pfWrite = 2;
        size_t writable;
        ulong low = ulong.max, high;
        foreach (ref header; info.dlpi_phdr[0 .. info.dlpi_phnum])
        {
            if (header.p_type == ptLoad)
            {
                low = header.p_vaddr < low ? header.p_vaddr : low;
                high = header.p_vaddr + header.p_memsz > high ? header.p_vaddr + header.p_memsz : high;
                if ((header.p_flags & pfWrite) != 0)
                {
                    ++writable;
                    main.segment = Span(header.p_vaddr, header.p_vaddr + header.p_memsz);
                }
            }
            else if (header.p_type == ptNote)
                main.buildId = noteBuildId(cast(const(ubyte)*)(info.dlpi_addr + header.p_vaddr),
                        cast(size_t) header.p_memsz, main.buildId);
        }
        main.bias = info.dlpi_addr;
        main.image = Span(info.dlpi_addr + low, info.dlpi_addr + high);
        main.found = writable == 1;
        return 1; // the first object is the main program
    }

    // SAFETY: Reads the `size` bytes of one mapped PT_NOTE segment, bounds-checked note by note.
    private ulong noteBuildId(const(ubyte)* notes, size_t size, ulong found) @trusted nothrow @nogc
    {
        const bytes = notes[0 .. size];
        size_t at;
        while (at + 12 <= size)
        {
            const namesz = u32(bytes, at), descsz = u32(bytes, at + 4), type = u32(bytes, at + 8);
            const desc = at + 12 + ((namesz + 3) & ~3);
            if (desc + descsz > size)
                break;
            if (type == 3 && namesz == 4 && bytes[at + 12 .. at + 16] == ['G', 'N', 'U', 0] && descsz >= 8)
                return u64(bytes, desc);
            at = desc + ((descsz + 3) & ~3);
        }
        return found;
    }
}

/// What reading the map found.
private enum Found
{
    none,
    damaged,
    map,
}

/// Read the map at the end of `/proc/self/exe` into `blob` (malloc'd, the caller frees it).
// SAFETY: Reads into a local trailer and a malloc'd buffer of exactly the size read; the descriptor is closed on
// every path.
private @trusted Found readMap(out Trailer trailer, out ubyte[] blob) nothrow @nogc
{
    version (linux)
    {
        import core.stdc.stdlib : free, malloc;
        import core.sys.posix.fcntl : O_CLOEXEC, O_RDONLY, open;
        import core.sys.posix.sys.stat : fstat, stat_t;
        import core.sys.posix.unistd : close, pread;

        const fd = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
        if (fd < 0)
            return Found.none;
        scope (exit)
            close(fd);
        stat_t info;
        if (fstat(fd, &info) != 0 || info.st_size < trailerBytes)
            return Found.none;
        ubyte[trailerBytes] tail;
        const end = info.st_size;
        if (pread(fd, tail.ptr, trailerBytes, end - trailerBytes) != trailerBytes || tail[0 .. 8] != mapMagic[])
            return Found.none;
        if (!parseTrailer(tail[], trailer) || trailer.blobBytes + trailerBytes > cast(ulong) end)
            return Found.damaged;
        auto buffer = cast(ubyte*) malloc(cast(size_t) trailer.blobBytes);
        if (buffer is null)
            return Found.damaged;
        const size = cast(size_t) trailer.blobBytes;
        if (pread(fd, buffer, size, end - trailerBytes - size) != size || checksum(buffer[0 .. size],
                tail[]) != trailer.checksum)
        {
            free(buffer);
            return Found.damaged;
        }
        blob = buffer[0 .. size];
        return Found.map;
    }
    else
        return Found.none;
}

/// The map's audit request, or the environment's (`FLINT_GC_STATIC_VERIFY=1|0`).
// SAFETY: getenv returns a NUL-terminated string the environment owns; it is only read here.
private @trusted bool auditRequested(bool mapAsks) nothrow @nogc
{
    import core.stdc.stdlib : getenv;
    import core.stdc.string : strlen;

    auto value = getenv("FLINT_GC_STATIC_VERIFY");
    if (value is null)
        return mapAsks;
    const text = value[0 .. strlen(value)];
    return text != "0" && text != "off" && text != "false";
}

/// Whether to audit a binary without a map: `byDefault` (debug builds), unless the environment says otherwise.
bool auditWanted(bool byDefault) nothrow @nogc
{
    return auditRequested(byDefault);
}

// SAFETY: As auditRequested.
private @trusted TrimMode environmentMode() nothrow @nogc
{
    import core.stdc.stdlib : getenv;
    import core.stdc.string : strlen;

    auto value = getenv("FLINT_GC_STATIC_TRIM");
    return value is null ? TrimMode.full : trimMode(value[0 .. strlen(value)]);
}

/// The spans the audit watcher checks: the region minus the keep list.
private __gshared Span* auditSpans;
private __gshared size_t auditCount;
/// The main executable's mapped image, for the audit's quick rejection of static addresses.
private __gshared Span image;

/// The loaded main executable's address range; empty before startup or without dl_iterate_phdr.
// SAFETY: Written once at startup, read-only afterwards.
@trusted Span executableImage() nothrow @nogc
{
    return image;
}

/// Apply the executable's map, once, from a module constructor after the RELRO trim and before other threads.
// SAFETY: Frees the blob readMap allocated on every path; the rest is in the safe helpers below.
@trusted void applyStaticMap() nothrow
{
    import core.stdc.stdlib : free;

    Executable main;
    version (linux)
        dl_iterate_phdr(&describeMain, &main);
    image = main.image;
    Trailer trailer;
    ubyte[] blob;
    const found = readMap(trailer, blob);
    if (found != Found.map)
    {
        state = found == Found.damaged ? MapState.mismatched : MapState.absent;
        return;
    }
    scope (exit)
        free(blob.ptr);
    const mode = environmentMode();
    const audit = auditRequested((trailer.flags & auditFlag) != 0);
    if (mode == TrimMode.off && !audit)
        state = MapState.disabled;
    else
        state = useMap(main, trailer, blob, mode == TrimMode.off ? TrimMode.full : mode, audit);
    reportState(mode);
}

/// With `FLINT_GC_STATIC_REPORT` set, one line on stderr: what became of the map (diagnostics and A/B runs).
// SAFETY: getenv's string is only tested for presence; fprintf formats this module's scalars.
private @trusted void reportState(TrimMode mode) nothrow @nogc
{
    import core.stdc.stdio : fprintf, stderr;
    import core.stdc.stdlib : getenv;

    if (getenv("FLINT_GC_STATIC_REPORT") is null)
        return;
    static immutable string[5] states = ["absent", "mismatched", "disabled", "audited", "applied"];
    static immutable string[3] modes = ["full", "provable", "off"];
    fprintf(stderr, "Flint static data: map=%.*s mode=%.*s dropped=%llu\n",
            cast(int) states[state].length, states[state].ptr, cast(int) modes[mode].length,
            modes[mode].ptr, cast(ulong) droppedBytes);
}

/// Validate the map against the loaded executable and the registered range, then trim, or remember the audit.
// SAFETY: Runs once from the module constructor before other threads; it writes this module's startup state.
private @trusted MapState useMap(const ref Executable main, const ref Trailer trailer,
        scope const(ubyte)[] blob, TrimMode mode, bool audit) nothrow
{
    if (!main.found || main.segment != Span(trailer.segmentAddress,
            trailer.segmentAddress + trailer.segmentSize) || (trailer.buildId != 0
            && main.buildId != trailer.buildId) || !registered(main.bias + trailer.regionBegin,
            main.bias + trailer.regionEnd))
        return MapState.mismatched;
    Span[maxSpans] spans;
    size_t count;
    if (!keepList(blob, trailer, mode, spans[], count))
        return MapState.mismatched;
    ulong kept;
    foreach (span; spans[0 .. count])
        kept += span.end - span.begin;
    droppedBytes = (trailer.regionEnd - trailer.regionBegin) - kept;
    if (audit)
    {
        rememberAudit(trailer, spans[0 .. count], main.bias);
        return MapState.audited;
    }
    replaceRange(main.bias, trailer, spans[0 .. count]);
    return MapState.applied;
}

/// Whether druntime registered exactly `[begin, end)`: the range the RELRO trim left for this segment.
// SAFETY: Walks the collector's own range list through its iterator; nothing is dereferenced.
private @trusted bool registered(ulong begin, ulong end) nothrow
{
    bool found;
    try
    {
        foreach (ref range; gc_getProxy().rangeIter)
            found = found || (range.pbot is cast(void*) begin && range.ptop is cast(void*) end);
    }
    catch (Exception)
        return false; // an unknown collector: keep the whole range
    return found;
}

/// Replace the region's registered range by the keep spans, at their loaded addresses.
// SAFETY: Each new range lies inside the executable's writable segment, mapped for the program's lifetime; the
// collector's lock is taken per call, after the iteration in `registered` has ended.
private @trusted void replaceRange(ulong bias, const ref Trailer trailer, scope const Span[] keep) nothrow @nogc
{
    auto collector = gc_getProxy();
    collector.removeRange(cast(void*)(bias + trailer.regionBegin));
    foreach (span; keep)
    {
        // Whole words only, as flint build writes them: a range starting mid-word would hide its pointers.
        const begin = (bias + span.begin) & ~7UL;
        const end = (bias + span.end + 7) & ~7UL;
        const low = begin < bias + trailer.regionBegin ? bias + trailer.regionBegin : begin;
        const high = end > bias + trailer.regionEnd ? bias + trailer.regionEnd : end;
        collector.addRange(cast(void*) low, cast(size_t)(high - low), null);
    }
}

/// Keep the complement of `keep` within the region, at its loaded addresses, for the audit watcher.
// SAFETY: Writes at most count + 1 spans into a malloc'd array of that capacity, kept for the process lifetime.
private @trusted void rememberAudit(const ref Trailer trailer, scope const Span[] keep, ulong bias) nothrow @nogc
{
    import core.stdc.stdlib : malloc;

    auto spans = cast(Span*) malloc((keep.length + 1) * Span.sizeof);
    if (spans is null)
        return;
    size_t count;
    ulong at = trailer.regionBegin;
    foreach (span; keep)
    {
        if (span.begin > at)
            spans[count++] = Span(bias + at, bias + span.begin);
        at = span.end;
    }
    if (at < trailer.regionEnd)
        spans[count++] = Span(bias + at, bias + trailer.regionEnd);
    auditSpans = spans;
    auditCount = count;
}

/// The audit's spans (loaded addresses), empty outside audit mode.
// SAFETY: Written once at startup, read-only afterwards.
@trusted const(Span)[] auditedSpans() nothrow @nogc
{
    return auditSpans is null ? null : auditSpans[0 .. auditCount];
}

/// druntime's current collector (core.internal.gc.proxy).
private extern (C) GC gc_getProxy() nothrow @nogc;

private uint u32(scope const(ubyte)[] data, size_t at) pure nothrow @nogc
{
    if (at + 4 > data.length)
        return 0;
    uint value;
    foreach (i; 0 .. 4)
        value |= cast(uint) data[at + i] << (8 * i);
    return value;
}

private ulong u64(scope const(ubyte)[] data, size_t at) pure nothrow @nogc
{
    if (at + 8 > data.length)
        return 0;
    ulong value;
    foreach (i; 0 .. 8)
        value |= cast(ulong) data[at + i] << (8 * i);
    return value;
}

@("FLINT_GC_STATIC_TRIM selects the mode: off, provable, or full by default")
unittest
{
    assert(trimMode("0") == TrimMode.off && trimMode("off") == TrimMode.off && trimMode("false") == TrimMode.off);
    assert(trimMode("provable") == TrimMode.provable);
    assert(trimMode("1") == TrimMode.full && trimMode("") == TrimMode.full && trimMode("full") == TrimMode.full);
}

@("a trailer is recognised by its magic, its blob size bound and a non-empty region")
unittest
{
    ubyte[trailerBytes] bytes;
    bytes[0 .. 8] = mapMagic[];
    bytes[8] = 40; // blob bytes
    bytes[32] = 0x10; // region begin
    bytes[40] = 0x20; // region end
    Trailer trailer;
    assert(parseTrailer(bytes[], trailer) && trailer.blobBytes == 40 && trailer.regionEnd == 0x20);
    bytes[0] = 'X';
    assert(!parseTrailer(bytes[], trailer));
    bytes[0] = 'F';
    bytes[40] = 0x10; // empty region
    assert(!parseTrailer(bytes[], trailer));
}

@("keep lists are read for the chosen mode and rejected when unsorted, overlapping or outside the region")
unittest
{
    ubyte[] blob;
    void put(ulong value, size_t bytes)
    {
        foreach (i; 0 .. bytes)
            blob ~= cast(ubyte)(value >> (8 * i));
    }

    put(1, 4); // provable: one span
    put(2, 4); // full: two spans
    put(0x1000, 8);
    put(0x2000, 8);
    put(0x1000, 8);
    put(0x1100, 8);
    put(0x1f00, 8);
    put(0x2000, 8);
    Trailer trailer;
    trailer.regionBegin = 0x1000;
    trailer.regionEnd = 0x2000;
    Span[4] spans;
    size_t count;
    assert(keepList(blob, trailer, TrimMode.provable, spans[], count) && count == 1 && spans[0] == Span(0x1000, 0x2000));
    assert(keepList(blob, trailer, TrimMode.full, spans[], count) && count == 2 && spans[1] == Span(0x1f00, 0x2000));
    // A mid-word start is refused: the collector would misread every pointer in that range.
    blob[8 + 16] = 0x04;
    assert(!keepList(blob, trailer, TrimMode.full, spans[], count));
    blob[8 + 16] = 0x00;
    trailer.regionEnd = 0x1f80; // the last span now leaves the region
    assert(!keepList(blob, trailer, TrimMode.full, spans[], count));
    assert(!keepList(blob[0 .. $ - 1], trailer, TrimMode.provable, spans[], count)); // truncated
}
