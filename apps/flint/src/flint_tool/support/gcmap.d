/++
The static-data map: which bytes of an executable's writable static data can hold a pointer into the GC heap.

druntime registers each writable PT_LOAD segment of a D program as one GC root range, and every collection reads it
word by word. flint.arena already cuts the RELRO part out at startup. Most of what is left is class metadata
(ClassInfo and TypeInfo objects), class and struct `__init` images and ModuleInfo, none of which ever holds a GC
pointer (docs/spring/phase1/gc.md, section 3c). On petclinic-rest that is 466 of 484 KiB of `.data`.

After the link, flint classifies the executable's symbols and appends the map to the file, after everything the
loader maps. A trailer at the very end lets flint.arena find, validate and apply it at startup
(flint.arena.sys.gc.static_map). Stripping the binary drops the map, and the program then scans the whole segment
as before.

The map has two keep lists:
$(UL
    $(LI provable: everything except `__init` images, ModuleInfo, the `__minfo` table and alignment padding;)
    $(LI full: the provable list, also without ClassInfo and TypeInfo objects. Their only word that could hold a GC
        pointer is the monitor, under the rule "class metadata never owns a GC monitor" (decision e170ffd0).)
)
+/
module flint_tool.support.gcmap;

import std.algorithm.sorting : sort;

@safe:

/// The trailer's magic, at both its ends' readers' fixed offsets.
enum ubyte[8] mapMagic = ['F', 'L', 'G', 'C', 'M', 'A', 'P', '1'];
/// The trailer's size: magic, blob size, segment address and size, region bounds, build-id prefix, flags, checksum.
enum size_t trailerBytes = 64;
/// Flag: the program audits the trimmed data at run time (debug and test profiles).
enum uint verifyFlag = 1;

/// A half-open address interval `[begin, end)`.
struct Span
{
    /// The first address.
    ulong begin;
    /// One past the last address.
    ulong end;
}

/// What the classification decided for one executable.
struct StaticMap
{
    /// The writable PT_LOAD segment the map belongs to.
    ulong segmentAddress, segmentSize;
    /// The part of it druntime still registers after flint.arena's RELRO trim: the map's domain.
    Span region;
    /// The first eight bytes of the GNU build-id, little-endian; zero without one.
    ulong buildId;
    /// Ranges to keep scanning, sorted and disjoint, inside `region`.
    Span[] provable;
    /// ditto, with class metadata dropped too.
    Span[] full;
}

/// The kinds of static data flint distinguishes by mangled name.
enum DataKind
{
    /// Ordinary data: a D or C variable, or an array literal's storage. Always scanned.
    keep,
    /// A class or struct `__init` image, ModuleInfo, or the `__minfo` table: static, never a GC pointer.
    provable,
    /// A ClassInfo or TypeInfo object: static except for its monitor word.
    classMetadata,
}

/// The kind of the static symbol `name`.
DataKind dataKind(scope const(char)[] name) pure nothrow @nogc
{
    if (!startsWith(name, "_D"))
        return DataKind.keep;
    if (endsWith(name, "7__ClassZ") || endsWith(name, "11__InterfaceZ"))
        return DataKind.classMetadata;
    if (endsWith(name, "12__ModuleInfoZ"))
        return DataKind.provable;
    if (endsWith(name, "6__initZ"))
        return isTypeInfoInstance(name) ? DataKind.classMetadata : DataKind.provable;
    return DataKind.keep;
}

/// Whether `name` (`_D<length>TypeInfo_...6__initZ`) is a TypeInfo object rather than a type's init image.
private bool isTypeInfoInstance(scope const(char)[] name) pure nothrow @nogc
{
    size_t at = 2;
    while (at < name.length && name[at] >= '0' && name[at] <= '9')
        ++at;
    return at > 2 && startsWith(name[at .. $], "TypeInfo_");
}

private bool startsWith(scope const(char)[] text, scope const(char)[] prefix) pure nothrow @nogc
{
    return text.length >= prefix.length && text[0 .. prefix.length] == prefix;
}

private bool endsWith(scope const(char)[] text, scope const(char)[] suffix) pure nothrow @nogc
{
    return text.length >= suffix.length && text[$ - suffix.length .. $] == suffix;
}

/// A symbol inside the region, with the kind of data it holds.
struct Placed
{
    /// Where the symbol lies.
    Span span;
    /// What it holds.
    DataKind kind;
}

/// Gaps between symbols shorter than this are alignment padding: no object fits, and none is named there.
private enum ulong paddingBytes = 16;
/// Kept ranges this close together are merged: scanning a few dropped bytes costs less than one more range.
private enum ulong mergeBytes = 64;

/// The ranges of `region` to keep scanning when the symbols of the kinds in `dropped` are not scanned.
Span[] keepRanges(Span region, scope Placed[] symbols, scope const DataKind[] dropped, scope const Span[] alwaysDropped)
{
    auto drops = droppedSpans(symbols, dropped, alwaysDropped);
    Span[] all;
    foreach (symbol; symbols)
        all ~= symbol.span;
    all ~= alwaysDropped;
    sort!((a, b) => a.begin < b.begin)(all);
    extendOverPadding(drops, all);
    auto keep = complement(region, drops);
    // A symbol of a kept kind is scanned even where a dropped one overlaps it (an alias, say): keeping wins.
    foreach (symbol; symbols)
        if (!isDropped(symbol.kind, dropped))
            keep ~= symbol.span;
    sort!((a, b) => a.begin < b.begin)(keep);
    return mergeClose(aligned(keep, region));
}

/// The spans widened to whole words, inside `region`: the collector reads a root range a word at a time from its
/// start, so a range that starts mid-word would misread every pointer in it. Scanning a few more bytes is safe.
private Span[] aligned(scope const Span[] spans, Span region)
{
    enum ulong word = 8;
    Span[] widened;
    foreach (span; spans)
    {
        const begin = span.begin & ~(word - 1);
        const end = (span.end + word - 1) & ~(word - 1);
        widened ~= Span(begin < region.begin ? region.begin : begin, end > region.end ? region.end : end);
    }
    return widened;
}

private bool isDropped(DataKind kind, scope const DataKind[] dropped) pure nothrow @nogc
{
    foreach (candidate; dropped)
        if (kind == candidate)
            return true;
    return false;
}

/// The spans of the symbols of the dropped kinds, and the sections always dropped, sorted.
private Span[] droppedSpans(scope Placed[] symbols, scope const DataKind[] dropped, scope const Span[] alwaysDropped)
{
    Span[] drops;
    foreach (symbol; symbols)
        if (isDropped(symbol.kind, dropped))
            drops ~= symbol.span;
    drops ~= alwaysDropped;
    sort!((a, b) => a.begin < b.begin)(drops);
    return drops;
}

/// Extend each drop over the padding that follows it, up to the next symbol (both lists are sorted).
private void extendOverPadding(Span[] drops, scope const Span[] all) pure nothrow @nogc
{
    size_t next;
    foreach (ref drop; drops)
    {
        while (next < all.length && all[next].begin < drop.end)
            ++next;
        if (next < all.length && all[next].begin - drop.end < paddingBytes)
            drop.end = all[next].begin;
    }
}

/// `region` without the sorted `drops`.
private Span[] complement(Span region, scope const Span[] drops)
{
    Span[] keep;
    ulong at = region.begin;
    foreach (drop; drops)
    {
        const begin = drop.begin < region.begin ? region.begin : drop.begin;
        const end = drop.end > region.end ? region.end : drop.end;
        if (end <= at)
            continue;
        if (begin > at)
            keep ~= Span(at, begin);
        at = end;
    }
    if (at < region.end)
        keep ~= Span(at, region.end);
    return keep;
}

/// Sorted spans merged where they overlap or lie within `mergeBytes` of each other.
private Span[] mergeClose(scope const Span[] sorted)
{
    Span[] merged;
    foreach (span; sorted)
    {
        if (merged.length != 0 && span.begin <= merged[$ - 1].end + mergeBytes)
        {
            if (span.end > merged[$ - 1].end)
                merged[$ - 1].end = span.end;
        }
        else
            merged ~= span;
    }
    return merged;
}

/// The ELF header's fields the map reads.
private struct Header
{
    ulong phoff, shoff;
    uint phentsize, phnum, shentsize, shnum, shstrndx;
}

/// The header of an ELF64 little-endian program (one with an entry point), if `elf` is one.
private bool readHeader(scope const(ubyte)[] elf, out Header header)
{
    if (elf.length < 64 || elf[0 .. 4] != [0x7f, 'E', 'L', 'F'] || elf[4] != 2 || elf[5] != 1)
        return false;
    if (u64(elf, 24) == 0) // no entry point: a shared library, not a program
        return false;
    header = Header(u64(elf, 32), u64(elf, 40), u16(elf, 54), u16(elf, 56), u16(elf, 58), u16(elf, 60), u16(elf, 62));
    return header.phentsize >= 56 && header.shentsize >= 64
        && header.phoff + header.phnum * header.phentsize <= elf.length
        && header.shoff + header.shnum * header.shentsize <= elf.length && header.shstrndx < header.shnum;
}

/// The single writable segment, the RELRO span and the build-id; `false` without exactly one writable segment.
private bool readSegments(scope const(ubyte)[] elf, const ref Header header, ref StaticMap map, out Span relro)
{
    enum uint ptLoad = 1, ptNote = 4, ptRelro = 0x6474e552, pfWrite = 2;
    size_t writable;
    foreach (i; 0 .. header.phnum)
    {
        const at = header.phoff + i * header.phentsize;
        const type = u32(elf, at);
        const vaddr = u64(elf, at + 16), memsz = u64(elf, at + 40);
        if (type == ptLoad && (u32(elf, at + 4) & pfWrite) != 0)
        {
            ++writable;
            map.segmentAddress = vaddr;
            map.segmentSize = memsz;
        }
        else if (type == ptRelro)
            relro = Span(vaddr, vaddr + memsz);
        else if (type == ptNote)
            readBuildId(elf, u64(elf, at + 8), u64(elf, at + 32), map.buildId);
    }
    return writable == 1;
}

/// The map of an ELF64 little-endian executable, or `false` when it has no single writable segment or no symbol
/// table to classify.
bool buildMap(scope const(ubyte)[] elf, out StaticMap map)
{
    Header header;
    Span relro;
    if (!readHeader(elf, header) || !readSegments(elf, header, map, relro))
        return false;
    // flint.arena's RELRO trim keeps the segment after the last whole RELRO page.
    enum ulong page = 4096;
    const segmentEnd = map.segmentAddress + map.segmentSize;
    ulong begin = map.segmentAddress;
    if (relro.end > relro.begin && relro.begin <= map.segmentAddress && (relro.end & ~(page - 1)) > begin)
        begin = relro.end & ~(page - 1);
    if (begin >= segmentEnd)
        return false;
    map.region = Span(begin, segmentEnd);

    Placed[] symbols;
    Span[] minfo;
    if (!readSymbols(elf, header.shoff, header.shnum, header.shentsize, header.shstrndx, map.region, symbols, minfo))
        return false;
    map.provable = keepRanges(map.region, symbols, [DataKind.provable], minfo);
    map.full = keepRanges(map.region, symbols, [DataKind.provable, DataKind.classMetadata], minfo);
    return true;
}

private void readBuildId(scope const(ubyte)[] elf, ulong offset, ulong size, ref ulong id)
{
    enum uint ntGnuBuildId = 3;
    ulong at = offset;
    const end = offset + size;
    while (at + 12 <= end && end <= elf.length)
    {
        const namesz = u32(elf, at), descsz = u32(elf, at + 4), type = u32(elf, at + 8);
        const name = at + 12, desc = name + ((namesz + 3) & ~3UL);
        if (desc + descsz > end)
            return;
        if (type == ntGnuBuildId && namesz == 4 && elf[name .. name + 4] == ['G', 'N', 'U', 0] && descsz >= 8)
        {
            id = u64(elf, desc);
            return;
        }
        at = desc + ((descsz + 3) & ~3UL);
    }
}

/// The symbols inside `region`, and the `__minfo` table's span there.
private bool readSymbols(scope const(ubyte)[] elf, ulong shoff, uint shnum, uint shentsize,
        uint shstrndx, Span region, ref Placed[] symbols, ref Span[] minfo)
{
    enum uint shtSymtab = 2;
    enum ubyte sttTls = 6;
    const names = shoff + shstrndx * shentsize;
    const namesOffset = u64(elf, names + 24);
    bool found;
    foreach (i; 0 .. shnum)
    {
        const at = shoff + i * shentsize;
        const name = cString(elf, namesOffset + u32(elf, at));
        if (name == "__minfo")
        {
            const addr = u64(elf, at + 16), size = u64(elf, at + 32);
            if (addr >= region.begin && addr + size <= region.end)
                minfo ~= Span(addr, addr + size);
        }
        if (u32(elf, at + 4) != shtSymtab)
            continue;
        const offset = u64(elf, at + 24), size = u64(elf, at + 32), entsize = u64(elf, at + 56);
        const link = u32(elf, at + 40);
        if (entsize < 24 || offset + size > elf.length || link >= shnum)
            return false;
        const strings = u64(elf, shoff + link * shentsize + 24);
        for (ulong entry = offset; entry + 24 <= offset + size; entry += entsize)
        {
            const value = u64(elf, entry + 8), bytes = u64(elf, entry + 16);
            if (bytes == 0 || (elf[entry + 4] & 0xf) == sttTls || value < region.begin || value + bytes > region.end)
                continue;
            const symbol = cString(elf, strings + u32(elf, entry));
            symbols ~= Placed(Span(value, value + bytes), dataKind(symbol));
        }
        found = true;
    }
    return found;
}

/// Whether every keep span starts and ends on a whole word (or at the region's end): the collector reads a root
/// range a word at a time from its start, and a range that starts mid-word hides every pointer in it.
bool wordAligned(const ref StaticMap map) pure nothrow @nogc
{
    foreach (list; [map.provable, map.full])
        foreach (span; list)
            if (span.begin % 8 != 0 || (span.end % 8 != 0 && span.end != map.region.end))
                return false;
    return true;
}

/// The bytes to append; throws when a keep span is not word-aligned, so a classification bug fails the build at
/// link time instead of hiding pointers from the collector.
ubyte[] encodeMap(const ref StaticMap map, bool verify)
{
    if (!wordAligned(map))
        throw new Exception("static-data map: a keep range is not word-aligned (flint_tool.support.gcmap)");
    ubyte[] blob;
    put32(blob, cast(uint) map.provable.length);
    put32(blob, cast(uint) map.full.length);
    foreach (list; [map.provable, map.full])
        foreach (span; list)
        {
            put64(blob, span.begin);
            put64(blob, span.end);
        }
    ubyte[] trailer;
    trailer ~= mapMagic[];
    put64(trailer, blob.length);
    put64(trailer, map.segmentAddress);
    put64(trailer, map.segmentSize);
    put64(trailer, map.region.begin);
    put64(trailer, map.region.end);
    put64(trailer, map.buildId);
    put32(trailer, verify ? verifyFlag : 0);
    put32(trailer, checksum(blob, trailer));
    assert(trailer.length == trailerBytes);
    return blob ~ trailer;
}

/// FNV-1a over the blob and the trailer before its checksum field.
uint checksum(scope const(ubyte)[] blob, scope const(ubyte)[] trailerHead) pure nothrow @nogc
{
    uint hash = 2_166_136_261;
    foreach (part; [blob, trailerHead[0 .. trailerBytes - 4]])
        foreach (b; part)
            hash = (hash ^ b) * 16_777_619;
    return hash;
}

/// The length of the executable without a map appended earlier (a rebuild may replay the same file).
size_t withoutMap(scope const(ubyte)[] file) pure nothrow @nogc
{
    if (file.length < trailerBytes || file[$ - trailerBytes .. $ - trailerBytes + 8] != mapMagic[])
        return file.length;
    const blob = u64(file, file.length - trailerBytes + 8);
    return blob + trailerBytes <= file.length ? cast(size_t)(file.length - trailerBytes - blob) : file.length;
}

/// Whether programs built with the profile `configuration` audit their trimmed static data at run time: every
/// profile but the optimised ones (release, size), so debug builds and `flint test` catch a violation.
bool auditsStaticData(scope const(char)[] configuration) pure nothrow @nogc
{
    return configuration != "release" && configuration != "size";
}

/// Append the static-data map to the executable `artifact`, replacing an earlier one. Returns the milliseconds it
/// took, or -1 when the file is no executable flint can map (a library, a stripped or foreign file): the program
/// then scans its whole segment, as without the map. An unchanged map is not rewritten. A new one goes to a fresh
/// file renamed over the artifact (a hard link to a cached copy keeps the cached bytes), with the artifact's mode and
/// times: its time is the build's start (`stampBuilt`), which up-to-date checks compare with edits.
long attachStaticMap(string artifact, bool verify)
{
    import core.time : MonoTime;
    import std.file : FileException, getAttributes, read, rename, setAttributes, setTimes, timeLastModified, write;

    const started = MonoTime.currTime;
    const(ubyte)[] file;
    try
        file = cast(const(ubyte)[]) read(artifact);
    catch (FileException)
        return -1;
    const original = withoutMap(file);
    StaticMap map;
    if (!buildMap(file[0 .. original], map))
        return -1;
    const encoded = encodeMap(map, verify);
    if (file[original .. $] == encoded)
        return (MonoTime.currTime - started).total!"msecs";
    try
    {
        const modified = timeLastModified(artifact);
        const mode = getAttributes(artifact);
        const fresh = artifact ~ ".gcmap";
        write(fresh, file[0 .. original] ~ encoded);
        setAttributes(fresh, mode);
        setTimes(fresh, modified, modified);
        rename(fresh, artifact);
    }
    catch (FileException)
        return -1;
    return (MonoTime.currTime - started).total!"msecs";
}

private void put32(ref ubyte[] out_, uint value)
{
    foreach (i; 0 .. 4)
        out_ ~= cast(ubyte)(value >> (8 * i));
}

private void put64(ref ubyte[] out_, ulong value)
{
    foreach (i; 0 .. 8)
        out_ ~= cast(ubyte)(value >> (8 * i));
}

private string cString(scope const(ubyte)[] data, ulong offset)
{
    if (offset >= data.length)
        return null;
    size_t end = cast(size_t) offset;
    while (end < data.length && data[end] != 0)
        ++end;
    return (cast(const(char)[]) data[cast(size_t) offset .. end]).idup;
}

private uint u16(scope const(ubyte)[] data, ulong at) pure nothrow @nogc
{
    return at + 2 <= data.length ? data[cast(size_t) at] | (data[cast(size_t) at + 1] << 8) : 0;
}

private uint u32(scope const(ubyte)[] data, ulong at) pure nothrow @nogc
{
    if (at + 4 > data.length)
        return 0;
    uint value;
    foreach (i; 0 .. 4)
        value |= cast(uint) data[cast(size_t) at + i] << (8 * i);
    return value;
}

private ulong u64(scope const(ubyte)[] data, ulong at) pure nothrow @nogc
{
    if (at + 8 > data.length)
        return 0;
    ulong value;
    foreach (i; 0 .. 8)
        value |= cast(ulong) data[cast(size_t) at + i] << (8 * i);
    return value;
}

@("static data kinds follow the mangled names of class metadata, init images and ModuleInfo")
unittest
{
    assert(dataKind("_D6object9Throwable7__ClassZ") == DataKind.classMetadata);
    assert(dataKind("_D6object6Object7Monitor11__InterfaceZ") == DataKind.classMetadata);
    assert(dataKind("_D10TypeInfo_i6__initZ") == DataKind.classMetadata);
    assert(dataKind("_D41TypeInfo_S5flint4core7NameMap6__initZ") == DataKind.classMetadata);
    assert(dataKind("_D5flint4core7NameMap6__initZ") == DataKind.provable);
    assert(dataKind("_D3std6socket12__ModuleInfoZ") == DataKind.provable);
    assert(dataKind("_D5flint2os3sys10interrupts11coordinatorSQBnQBkQBkQBj11Coordinator") == DataKind.keep);
    assert(dataKind(".dynarrayStorage.61") == DataKind.keep);
    assert(dataKind("ssl3_ciphers") == DataKind.keep);
}

@("keep ranges drop the chosen kinds and the padding after them, keep unknown gaps, and merge close neighbours")
unittest
{
    const region = Span(0x1000, 0x2000);
    Placed[] symbols = [
        Placed(Span(0x1000, 0x10a8), DataKind.classMetadata), // 168 bytes, then 8 bytes of padding
        Placed(Span(0x10b0, 0x10c0),
                DataKind.keep), Placed(Span(0x10c0, 0x1168), DataKind.classMetadata),
        Placed(Span(0x1200, 0x1300), DataKind.provable), // after a 0x98-byte gap with no symbol: unknown, kept
        Placed(Span(0x1300, 0x1f00), DataKind.classMetadata),
    ];
    const provable = keepRanges(region, symbols, [DataKind.provable], null);
    assert(provable == [Span(0x1000, 0x1200), Span(0x1300, 0x2000)]);
    const full = keepRanges(region, symbols, [DataKind.provable, DataKind.classMetadata], null);
    // The kept 16 bytes, the unknown gap before 0x1200, and the tail after the last symbol.
    assert(full == [Span(0x10b0, 0x10c0), Span(0x1168, 0x1200), Span(0x1f00, 0x2000)]);
}

@("keep ranges start and end on whole words, so the collector reads every pointer in them")
unittest
{
    const region = Span(0x1000, 0x2000);
    Placed[] symbols = [
        Placed(Span(0x1000, 0x1005), DataKind.classMetadata), // a 5-byte symbol: the next kept data starts mid-word
        Placed(Span(0x1005, 0x1015),
                DataKind.keep), Placed(Span(0x1040, 0x2000), DataKind.classMetadata),
    ];
    foreach (span; keepRanges(region, symbols, [DataKind.classMetadata], null))
        assert(span.begin % 8 == 0 && (span.end % 8 == 0 || span.end == region.end));
    assert(keepRanges(region, symbols, [DataKind.classMetadata], null)[0] == Span(0x1000, 0x1040));
    StaticMap misaligned;
    misaligned.region = region;
    misaligned.full = [Span(0x1005, 0x1040)];
    assert(!wordAligned(misaligned));
    bool refused;
    try
        cast(void) encodeMap(misaligned, false);
    catch (Exception)
        refused = true;
    assert(refused, "a map with a mid-word keep range was encoded");
}

@("an encoded map round-trips its lengths, ends in the magic and is replaced, not stacked, on a second attach")
unittest
{
    StaticMap map;
    map.segmentAddress = 0x1000;
    map.segmentSize = 0x3000;
    map.region = Span(0x2000, 0x4000);
    map.provable = [Span(0x2000, 0x3000)];
    map.full = [Span(0x2000, 0x2100), Span(0x3f00, 0x4000)];
    const encoded = encodeMap(map, true);
    assert(encoded.length == 8 + 3 * 16 + trailerBytes);
    assert(encoded[$ - trailerBytes .. $ - trailerBytes + 8] == mapMagic[]);
    const file = cast(const(ubyte)[]) "ELF bytes" ~ encoded;
    assert(withoutMap(file) == "ELF bytes".length);
    assert(withoutMap(cast(const(ubyte)[]) "ELF bytes") == "ELF bytes".length);
}
