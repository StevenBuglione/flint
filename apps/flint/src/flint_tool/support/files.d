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
