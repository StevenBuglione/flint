/// Deterministic tar and gzip writers for `flint package` (ADR-023): fixed ownership and timestamps, entries
/// in the order given, so the same inputs give byte-identical archives.
module flint_tool.support.archive;

@safe:

/// One archive entry.
struct Entry
{
    /// Path inside the archive, with forward slashes; directories end in `/`.
    string path;
    /// File contents (empty for directories).
    const(ubyte)[] data;
    /// Permission bits.
    uint mode = octal644;
}

/// rw-r--r--.
enum uint octal644 = 420;
/// rwxr-xr-x.
enum uint octal755 = 493;

/// A POSIX ustar archive of `entries`, owned by root, with modification time `mtime`.
ubyte[] tarArchive(scope const Entry[] entries, long mtime = 0)
{
    ubyte[] archive;
    foreach (ref entry; entries)
    {
        const directory = entry.path.length && entry.path[$ - 1] == '/';
        archive ~= header(entry.path, directory ? 0 : entry.data.length, entry.mode, mtime, directory);
        if (directory)
            continue;
        archive ~= entry.data;
        archive.length += (512 - entry.data.length % 512) % 512;
    }
    archive.length += 1024;
    return archive;
}

private ubyte[512] header(string path, size_t size, uint mode, long mtime, bool directory)
{
    ubyte[512] block;
    string name = path;
    string prefix;
    if (name.length > 100)
    {
        // ustar splits long paths at a slash: prefix (155 bytes) / name (100 bytes).
        size_t cut = name.length;
        foreach_reverse (i, ch; name[0 .. name.length > 156 ? 156 : name.length])
        {
            if (ch == '/' && name.length - i - 1 <= 100)
            {
                cut = i;
                break;
            }
        }
        assert(cut < name.length, "archive path too long for ustar: " ~ path);
        prefix = name[0 .. cut];
        name = name[cut + 1 .. $];
    }
    put(block[0 .. 100], name);
    put(block[100 .. 108], octalField(mode, 7));
    put(block[108 .. 116], octalField(0, 7));
    put(block[116 .. 124], octalField(0, 7));
    put(block[124 .. 136], octalField(size, 11));
    put(block[136 .. 148], octalField(mtime, 11));
    block[148 .. 156] = ' ';
    block[156] = directory ? '5' : '0';
    put(block[257 .. 263], "ustar");
    put(block[263 .. 265], "00");
    put(block[265 .. 269], "root");
    put(block[297 .. 301], "root");
    put(block[345 .. 500], prefix);
    uint sum;
    foreach (b; block)
        sum += b;
    put(block[148 .. 155], octalField(sum, 6) ~ "\0");
    return block;
}

private void put(scope ubyte[] field, scope const(char)[] text)
{
    assert(text.length <= field.length, "tar field overflow");
    foreach (i, ch; text)
        field[i] = cast(ubyte) ch;
}

private string octalField(ulong value, size_t digits)
{
    char[] text = new char[digits];
    foreach_reverse (ref ch; text)
    {
        ch = cast(char)('0' + (value & 7));
        value >>= 3;
    }
    return text.idup;
}

/// gzip of `data` with a zero timestamp and no file name.
ubyte[] gzip(scope const(ubyte)[] data)
{
    import flint_tool.sys.compress : gzipBytes;

    return gzipBytes(data);
}
