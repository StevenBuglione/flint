/// File helpers: hashing, deterministic writes and source discovery through flint.os.
module flint_tool.support.files;

import flint.os : GlobOptions, glob;

@safe:

/// Lower-case hexadecimal SHA-256 of bytes.
string sha256Hex(scope const(ubyte)[] bytes)
{
    import std.digest : LetterCase, toHexString;
    import std.digest.sha : sha256Of;

    return toHexString!(LetterCase.lower)(sha256Of(bytes)).idup;
}

/// SHA-256 of a file, or null when it cannot be read.
string sha256File(string path)
{
    import std.file : exists, isFile, read;

    if (!exists(path) || !isFile(path))
        return null;
    return sha256Hex(cast(const(ubyte)[]) read(path));
}

/// Where `cachedSha256File` keeps its digests: `<cache>/digests.log`, or nothing when null.
private string digestLog;
/// The digests read from the log, by path: `size mtime inode sha256`.
private string[string] digestRecords;
private bool digestsLoaded;
/// Size at which the digest log starts over.
private enum digestLogCap = 16 * 1024 * 1024;

/// Keep `cachedSha256File`'s digests under `cache` (FLINT_CACHE, else `<home>/.flint/cache`).
void useDigestCache(string cache)
{
    import std.path : buildPath;

    digestLog = cache.length ? buildPath(cache, "digests.log") : null;
    digestRecords = null;
    digestsLoaded = false;
}

/// SHA-256 of a file, reused while the file keeps its size, modification time and inode, as git's index trusts a
/// file's stat data. It is for the files a build reads every time and verifies nothing against: the toolchain's
/// executables, flint itself and the platform's sources. Downloads and lock verification hash in full
/// (`sha256File`). A file modified in the last two seconds could change again within the same timestamp, so its
/// digest is not recorded.
string cachedSha256File(string path)
{
    import std.conv : to;
    import std.datetime.systime : Clock;
    import std.file : DirEntry, FileException;

    if (digestLog is null)
        return sha256File(path);
    string stamp;
    long modified;
    try
    {
        auto entry = DirEntry(path);
        if (!entry.isFile)
            return null;
        modified = entry.timeLastModified.stdTime;
        stamp = entry.size.to!string ~ " " ~ modified.to!string ~ " " ~ inodeOf(entry);
    }
    catch (FileException)
        return null;
    loadDigests();
    if (auto record = path in digestRecords)
    {
        if ((*record).length == stamp.length + 65 && (*record)[0 .. stamp.length] == stamp)
            return (*record)[stamp.length + 1 .. $];
    }
    const digest = sha256File(path);
    if (digest.length && modified < Clock.currTime.stdTime - 20_000_000)
    {
        digestRecords[path] = stamp ~ " " ~ digest;
        appendDigest(path ~ "\t" ~ stamp ~ " " ~ digest ~ "\n");
    }
    return digest;
}

private void loadDigests()
{
    import std.algorithm.iteration : splitter;
    import std.algorithm.searching : findSplit;
    import std.file : exists, getSize, readText, remove;

    if (digestsLoaded)
        return;
    digestsLoaded = true;
    try
    {
        if (!exists(digestLog))
            return;
        // Every changed file appends a record. Past the cap, start over: the next builds record what they read.
        if (getSize(digestLog) > digestLogCap)
        {
            remove(digestLog);
            return;
        }
        foreach (line; readText(digestLog).splitter('\n'))
        {
            if (auto parts = line.findSplit("\t"))
                digestRecords[parts[0]] = parts[2];
        }
    }
    catch (Exception)
        digestRecords = null;
}

/// Append one record. Each record is one short write to a file opened for appending, so concurrent builds do not
/// interleave records; a later record for a path replaces an earlier one when the log is read.
private void appendDigest(string line)
{
    import std.file : append, mkdirRecurse;
    import std.path : dirName;

    try
    {
        mkdirRecurse(dirName(digestLog));
        append(digestLog, line);
    }
    catch (Exception)
    {
    }
}

private string inodeOf(ref imported!"std.file".DirEntry entry)
{
    import std.conv : to;

    version (Posix)
        return entry.statBuf.st_ino.to!string;
    else
        return "0";
}

/// Read a UTF-8 text file, or return null when it is missing.
string readIfPresent(string path)
{
    import std.file : exists, isFile, readText;

    if (!exists(path) || !isFile(path))
        return null;
    return readText(path);
}

/// Write `content` only when it differs, creating parent directories. Returns true when the file changed.
bool writeIfChanged(string path, scope const(char)[] content)
{
    import std.file : exists, mkdirRecurse, read, write;
    import std.path : dirName;

    if (exists(path) && cast(const(char)[]) read(path) == content)
        return false;
    mkdirRecurse(dirName(path));
    write(path, content);
    return true;
}

/// Root-relative paths of files under `root` matching `pattern`, sorted; empty when `root` is missing.
string[] findFiles(string root, string pattern)
{
    import std.file : exists, isDir, isFile;
    import std.path : buildPath;

    if (!exists(root) || !isDir(root))
        return null;
    auto found = glob(root, pattern, GlobOptions.init);
    if (!found.ok)
        return null;
    string[] files;
    foreach (relative; found.value)
    {
        if (isFile(buildPath(root, relative)))
            files ~= relative;
    }
    return files;
}

/// D sources below `root`, skipping cache directories (.flint, .dub). With `buildOutputs`, also skip any
/// `build` or `artifacts` directory, as tools/quality.py does for the workspace trees.
string[] dSources(string root, bool buildOutputs = false)
{
    string[] kept;
    foreach (relative; findFiles(root, "**/*.d"))
    {
        if (!skipped(relative, buildOutputs))
            kept ~= relative;
    }
    return kept;
}

/// Whether a root-relative path lies in a cache directory, or with `buildOutputs` in a build directory.
bool skipped(string relative, bool buildOutputs = true)
{
    import std.algorithm.iteration : splitter;

    foreach (part; relative.splitter('/'))
    {
        if (part == ".dub" || part == ".flint" || (buildOutputs && (part == "build" || part == "artifacts")))
            return true;
    }
    return false;
}

/// Path of `target` relative to `base`, with forward slashes.
string relativeTo(string target, string base)
{
    import std.path : absolutePath, buildNormalizedPath, relativePath;

    return relativePath(buildNormalizedPath(absolutePath(target)), buildNormalizedPath(absolutePath(base)));
}

@safe unittest
{
    import core.time : seconds;
    import std.conv : to;
    import std.datetime.systime : Clock;
    import std.file : exists, mkdirRecurse, readText, rmdirRecurse, setTimes, tempDir, write;
    import std.path : buildPath;
    import std.process : thisProcessID;

    const directory = buildPath(tempDir, "flint-digests-" ~ thisProcessID.to!string);
    scope (exit)
    {
        useDigestCache(null);
        if (exists(directory))
            rmdirRecurse(directory);
    }
    mkdirRecurse(directory);
    const file = buildPath(directory, "a.d");
    const old = Clock.currTime - 60.seconds;
    write(file, "one");
    setTimes(file, old, old);
    useDigestCache(buildPath(directory, "cache"));
    assert(cachedSha256File(file) == sha256File(file));
    const log = buildPath(directory, "cache", "digests.log");
    assert(readText(log).length > 0, "an old file's digest is recorded");

    useDigestCache(buildPath(directory, "cache"));
    assert(cachedSha256File(file) == sha256File(file), "read back from the log");
    write(file, "two!");
    setTimes(file, old, old);
    assert(cachedSha256File(file) == sha256File(file), "a new size is hashed again");

    const fresh = buildPath(directory, "b.d");
    write(fresh, "new");
    const before = readText(log);
    assert(cachedSha256File(fresh) == sha256File(fresh));
    assert(readText(log) == before, "a file modified just now is not recorded");
    assert(cachedSha256File(buildPath(directory, "missing.d")) is null);
}
