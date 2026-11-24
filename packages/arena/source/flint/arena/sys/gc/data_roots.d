/++
Trims the loader's read-only-after-relocation memory (PT_GNU_RELRO) out of the collector's root ranges.

druntime registers each D object's writable PT_LOAD segment (the executable and each D shared library) as one GC
root range, and every collection scans it word by word. The segment starts with the RELRO region: `.data.rel.ro`
and `.got`, which hold vtables, TypeInfo and generated tables. The loader protects that region read-only once it
has applied relocations, before any D constructor runs and before the collector allocates, so it can never hold a
pointer into the GC heap. On petclinic-rest it is 804 KB of a 1.79 MB segment.

The trim reads the collector's registered ranges, so it only changes ranges druntime registered for D objects, and
replaces each range that overlaps a protected region with the pieces outside it. A binary without RELRO is left as
it is. The protected region is the one the loader actually makes read-only: the RELRO start rounded down and its
end rounded down to whole pages, as glibc's and musl's loaders do.
+/
module flint.arena.sys.gc.data_roots;

import core.gc.gcinterface : GC, Range;

@safe:

/// The memory `[begin, end)`.
struct Region
{
    size_t begin;
    size_t end;
}

/// A registered range after the protected regions are cut out of it.
struct Trimmed
{
    /// The pieces to register in its place: zero, one or two.
    Region[2] pieces;
    size_t count;
    /// Whether a protected region overlapped the range at all.
    bool changed;
}

/// Cut the first protected region that overlaps `range` out of it (each object has at most one RELRO region, and a
/// registered range belongs to one object).
Trimmed trimRange(Region range, scope const(Region)[] protectedRegions) pure nothrow @nogc
{
    Trimmed result;
    foreach (cut; protectedRegions)
    {
        if (cut.begin >= cut.end || cut.end <= range.begin || cut.begin >= range.end)
            continue;
        result.changed = true;
        if (cut.begin > range.begin)
            result.pieces[result.count++] = Region(range.begin, cut.begin);
        if (cut.end < range.end)
            result.pieces[result.count++] = Region(cut.end, range.end);
        return result;
    }
    result.pieces[0] = range;
    result.count = 1;
    return result;
}

/// The page-aligned part of `[begin, begin + size)` that the loader protects: whole pages only.
Region protectedPages(size_t begin, size_t size, size_t page) pure nothrow @nogc
{
    const first = begin & ~(page - 1);
    const last = (begin + size) & ~(page - 1);
    return last > first ? Region(first, last) : Region(0, 0);
}

/// Most loaded objects the trim inspects, and most registered ranges it replaces.
private enum maxRegions = 64;

private struct Found
{
    Region[maxRegions] regions;
    size_t count;
    size_t page;
}

version (linux)
{
    import core.sys.linux.link : dl_iterate_phdr, dl_phdr_info;

    // SAFETY: The loader passes a valid info with dlpi_phnum headers for the call's duration; `data` is the caller's
    // live Found, written within its fixed capacity.
    private extern (C) int collectRelro(dl_phdr_info* info, size_t, void* data) @trusted nothrow @nogc
    {
        import core.sys.elf : PT_GNU_RELRO;

        auto found = cast(Found*) data;
        foreach (ref header; info.dlpi_phdr[0 .. info.dlpi_phnum])
        {
            if (header.p_type != PT_GNU_RELRO || found.count == maxRegions)
                continue;
            const region = protectedPages(info.dlpi_addr + header.p_vaddr, header.p_memsz, found.page);
            if (region.end > region.begin)
                found.regions[found.count++] = region;
        }
        return 0;
    }
}

/// Bytes the trim took out of the root ranges at startup; zero until it ran, or when there was nothing to trim.
private __gshared size_t trimmed;

// SAFETY: Reads one word that `trimReadOnlyRoots` writes once, from a module constructor, before other threads exist.
@trusted size_t trimmedBytes() nothrow @nogc
{
    return trimmed;
}

/// The protected regions of every loaded object (Linux); none elsewhere.
// SAFETY: dl_iterate_phdr calls collectRelro with the address of this frame's Found, which outlives the call.
private @trusted Found relroRegions() nothrow @nogc
{
    import core.memory : pageSize;

    Found found;
    found.page = pageSize;
    version (linux)
        dl_iterate_phdr(&collectRelro, &found);
    return found;
}

/// Replace every registered root range that overlaps a protected region with the pieces outside it. Call once, from
/// a module constructor: after druntime registered the data segments, before other threads run. The collector's lock
/// is not reentrant, so the overlapping ranges (at most maxRegions) are copied out before any is replaced.
// SAFETY: Reads the collector's own range list through its iterator, then removes and adds ranges outside it. Each
// new range lies inside one druntime registered, so it covers mapped memory for as long as the object is loaded.
@trusted void trimReadOnlyRoots()
{
    const found = relroRegions();
    if (found.count == 0)
        return;
    auto collector = gc_getProxy();
    Range[maxRegions] overlapping;
    size_t count;
    foreach (ref range; collector.rangeIter)
    {
        const span = Region(cast(size_t) range.pbot, cast(size_t) range.ptop);
        if (count < overlapping.length && trimRange(span, found.regions[0 .. found.count]).changed)
            overlapping[count++] = range;
    }
    size_t removed;
    foreach (ref range; overlapping[0 .. count])
    {
        const span = Region(cast(size_t) range.pbot, cast(size_t) range.ptop);
        const pieces = trimRange(span, found.regions[0 .. found.count]);
        collector.removeRange(range.pbot);
        size_t kept;
        foreach (piece; pieces.pieces[0 .. pieces.count])
        {
            collector.addRange(cast(void*) piece.begin, piece.end - piece.begin, range.ti);
            kept += piece.end - piece.begin;
        }
        removed += (span.end - span.begin) - kept;
    }
    trimmed = removed;
}

/// druntime's current collector (core.internal.gc.proxy).
private extern (C) GC gc_getProxy() nothrow @nogc;

@("a protected region is cut out of a range at its start, in its middle or whole, and others are left alone")
unittest
{
    const range = Region(0x1000, 0x5000);
    // RELRO at the segment's start, as linkers lay it out.
    auto start = trimRange(range, [Region(0x1000, 0x3000)]);
    assert(start.changed && start.count == 1 && start.pieces[0] == Region(0x3000, 0x5000));
    auto middle = trimRange(range, [Region(0x2000, 0x3000)]);
    assert(middle.changed && middle.count == 2);
    assert(middle.pieces[0] == Region(0x1000, 0x2000) && middle.pieces[1] == Region(0x3000, 0x5000));
    auto whole = trimRange(range, [Region(0x0, 0x6000)]);
    assert(whole.changed && whole.count == 0);
    // Another object's region, an empty one, or none: unchanged.
    foreach (regions; [[Region(0x6000, 0x7000)], [Region(0x2000, 0x2000)], cast(Region[]) null])
    {
        auto untouched = trimRange(range, regions);
        assert(!untouched.changed && untouched.count == 1 && untouched.pieces[0] == range);
    }
}

@("only the whole pages of a RELRO region count as protected, as the loader rounds them")
unittest
{
    assert(protectedPages(0x1010, 0x3000, 0x1000) == Region(0x1000, 0x4000));
    assert(protectedPages(0x1000, 0x2fff, 0x1000) == Region(0x1000, 0x3000));
    assert(protectedPages(0x1000, 0x800, 0x1000) == Region(0, 0));
}
