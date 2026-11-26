/++
The host process for flint:java and flint:core: environment variables, the process id and executable, file facts,
whole-file reads and writes, a directory's subdirectories, the current directory and path normalization, without std.process, std.file or std.path, whose
templates each caller instantiated (ADR-030 section 5, the template diet).

Everything here is `@safe` and `package(flint)`: framework modules call it, applications never do. The `@trusted`
calls live in `flint.engine.aot.sys.environment` and `flint.engine.aot.sys.files`. The behaviour is std.process's
and std.file's, except where a function's documentation says otherwise.
+/
module flint.engine.aot.host;

import flint.engine.aot.sys.environment : currentProcessId, readVariable;
import flint.engine.aot.sys.files : closeDirectory, closeFile, currentDirectoryInto, DirectoryHandle,
    FileHandle, nextEntryName, openDirectory, openRead, openWrite, readInto, statPath, writeFrom;
public import flint.engine.aot.sys.files : FileError, FileFacts;

@safe:

/// One environment variable.
struct EnvironmentEntry
{
    string name;
    string value;
}

/++
The value of the environment variable `name`, as `std.process.environment.get(name, defaultValue)`: `defaultValue`
when it is not set, `""` when it is set to the empty string. A name holding a NUL is never set.
+/
package(flint) string environmentVariable(scope const(char)[] name, string defaultValue = null) nothrow
{
    if (name.length == 0 || holdsNul(name))
        return defaultValue;
    version (Windows)
    {
        import flint.engine.aot.sys.files : narrow, widen;

        auto wide = widen(name);
        if (wide is null)
            return defaultValue;
        auto value = readVariable(wide);
        return value is null ? defaultValue : (value.length == 0 ? "" : narrow(value));
    }
    else
    {
        auto value = readVariable(nulTerminated(name));
        return value is null ? defaultValue : value;
    }
}

/++
Every environment variable, as `std.process.environment.toAA()` reads them but in the environment's order: when a
name occurs twice, the first wins. On Windows names are upper-cased (by Windows' own table, not std.uni's) and the
per-drive `=C:` entries are skipped.
+/
package(flint) EnvironmentEntry[] environmentEntries() nothrow
{
    EnvironmentEntry[] entries;
    version (Windows)
    {
        import flint.engine.aot.sys.environment : environmentBlock, upperCase;
        import flint.engine.aot.sys.files : narrow;

        const block = environmentBlock();
        size_t start;
        foreach (i, c; block)
        {
            if (c != '\0')
                continue;
            const entry = block[start .. i];
            start = i + 1;
            size_t equals;
            while (equals < entry.length && entry[equals] != '=')
                equals++;
            if (equals == 0 || equals == entry.length)
                continue;
            const value = narrow(entry[equals + 1 .. $]);
            addFirst(entries, narrow(upperCase(entry[0 .. equals])), value is null ? "" : value);
        }
    }
    else
    {
        import flint.engine.aot.sys.environment : environmentStrings = environmentEntries;

        foreach (entry; environmentStrings())
        {
            foreach (i, c; entry)
            {
                if (c == '=')
                {
                    addFirst(entries, entry[0 .. i], entry[i + 1 .. $]);
                    break;
                }
            }
        }
    }
    return entries;
}

private void addFirst(ref EnvironmentEntry[] entries, string name, string value) nothrow
{
    foreach (existing; entries)
        if (existing.name == name)
            return;
    entries ~= EnvironmentEntry(name, value);
}

/// This process's id, as std.process's `thisProcessID`.
package(flint) long processId() nothrow @nogc
{
    return currentProcessId();
}

/++
One `stat` of `path`, following symbolic links: whether it exists, is a regular file or a directory, its size and
its modification time. A path that is empty or holds a NUL does not exist.
+/
package(flint) FileFacts fileFacts(scope const(char)[] path) nothrow
{
    if (path.length == 0 || holdsNul(path))
        return FileFacts.init;
    version (Windows)
    {
        import flint.engine.aot.sys.files : widen;

        auto wide = widen(path);
        return wide is null ? FileFacts.init : statPath(wide);
    }
    else
        return statPath(nulTerminated(path));
}

/// Milliseconds since 1970-01-01T00:00Z of `facts.modifiedTicks`, as std.file's `timeLastModified(path)
/// .toUnixTime() * 1000`: whole seconds, truncated toward zero.
package(flint) long modifiedMillis(FileFacts facts) pure nothrow @nogc
{
    return facts.modifiedTicks / 10_000_000 * 1000;
}

/++
Every byte of the file at `path`, read to its end, as std.file's `read`; null with `error` set when it cannot be
opened or read. An empty file gives a non-null empty array.
+/
package(flint) ubyte[] readFile(scope const(char)[] path, out FileError error) nothrow
{
    if (path.length == 0 || holdsNul(path))
    {
        error = FileError.notFound;
        return null;
    }
    version (Windows)
    {
        import flint.engine.aot.sys.files : widen;

        auto name = widen(path);
        if (name is null)
        {
            error = FileError.notFound;
            return null;
        }
        enum FileHandle closed = null;
    }
    else
    {
        auto name = nulTerminated(path);
        enum FileHandle closed = -1;
    }
    auto file = openRead(name, error);
    if (file == closed)
        return null;
    scope (exit)
        closeFile(file);
    const facts = statPath(name);
    auto bytes = new ubyte[](facts.size > 0 && facts.size < int.max ? cast(size_t) facts.size + 1 : 4096);
    size_t length;
    for (;;)
    {
        if (length == bytes.length)
            bytes.length = bytes.length * 2;
        const count = readInto(file, bytes[length .. $]);
        if (count < 0)
        {
            error = FileError.other;
            return null;
        }
        if (count == 0)
            return bytes[0 .. length];
        length += count;
    }
}

/// The message Java's `FileInputStream` gives after the path for `error`: `No such file or directory`, ...
package(flint) string describe(FileError error) pure nothrow @nogc
{
    final switch (error)
    {
    case FileError.none:
        return "Success";
    case FileError.notFound:
        return "No such file or directory";
    case FileError.accessDenied:
        return "Permission denied";
    case FileError.isDirectory:
        return "Is a directory";
    case FileError.other:
        return "Input/output error";
    }
}

/++
The paths of the directories directly inside `directory`, unsorted: the names std.file's
`dirEntries(directory, SpanMode.shallow)` gives for the entries whose `isDir` holds, that is `directory` and the
entry joined by one separator, symbolic links followed, `.` and `..` left out. Null with `error` set when
`directory` cannot be listed (std.file throws).
+/
package(flint) string[] subdirectoryPaths(string directory, out FileError error) nothrow
{
    if (directory.length == 0 || holdsNul(directory))
    {
        error = FileError.notFound;
        return null;
    }
    DirectoryHandle listing;
    version (Windows)
    {
        import flint.engine.aot.sys.files : widen;

        const pattern = widen(isSeparator(directory[$ - 1]) ? directory ~ "*" : directory ~ "\\*");
        if (pattern is null)
        {
            error = FileError.notFound;
            return null;
        }
    }
    else
        const pattern = nulTerminated(directory);
    if (!openDirectory(pattern, listing, error))
        return null;
    scope (exit)
        closeDirectory(listing);
    string[] paths;
    for (auto name = nextEntryName(listing); name !is null; name = nextEntryName(listing))
    {
        if (name.length == 0 || name == "." || name == "..")
            continue;
        const path = joinPath(directory, name);
        if (fileFacts(path).directory)
            paths ~= path;
    }
    return paths;
}

/// The current working directory, as std.file's `getcwd`; null when it cannot be read.
package(flint) string currentDirectory() nothrow
{
    version (Windows)
    {
        import flint.engine.aot.sys.files : narrow;

        auto buffer = new wchar[](260);
    }
    else
        auto buffer = new char[](1024);
    for (;;)
    {
        const length = currentDirectoryInto(buffer);
        if (length == 0)
            return null;
        if (length <= buffer.length)
        {
            version (Windows)
                return narrow(buffer[0 .. length]);
            else
                return buffer[0 .. length].idup;
        }
        if (buffer.length >= 1 << 20)
            return null;
        buffer = new typeof(buffer[0])[](length > buffer.length * 2 ? length : buffer.length * 2);
    }
}

/++
Write `bytes` to the file at `path`, creating or truncating it, as std.file's `write`; false with `error` set when
it cannot be opened or written (std.file throws).
+/
package(flint) bool writeFile(scope const(char)[] path, scope const(ubyte)[] bytes, out FileError error) nothrow
{
    if (path.length == 0 || holdsNul(path))
    {
        error = FileError.notFound;
        return false;
    }
    version (Windows)
    {
        import flint.engine.aot.sys.files : widen;

        const name = widen(path);
        if (name is null)
        {
            error = FileError.notFound;
            return false;
        }
    }
    else
        const name = nulTerminated(path);
    auto file = openWrite(name, error);
    if (error != FileError.none)
        return false;
    scope (exit)
        closeFile(file);
    while (bytes.length)
    {
        const written = writeFrom(file, bytes);
        if (written <= 0)
        {
            error = FileError.other;
            return false;
        }
        bytes = bytes[written .. $];
    }
    return true;
}

/// The running executable's absolute path, as std.file's `thisExePath`; null when the platform does not say.
package(flint) string executablePath() nothrow
{
    version (Windows)
    {
        import flint.engine.aot.sys.files : executablePathWide, narrow;

        auto wide = executablePathWide();
        return wide is null ? null : narrow(wide);
    }
    else
    {
        import flint.engine.aot.sys.files : executablePathInto;

        for (size_t size = 1024; size <= 1 << 20; size *= 2)
        {
            auto buffer = new char[](size);
            const length = executablePathInto(buffer);
            if (length == 0)
                return null;
            if (length <= buffer.length)
                return buffer[0 .. length].idup;
        }
        return null;
    }
}

/++
`path` made absolute against the current directory, as std.path's `absolutePath(path)`: null for an empty path,
`path` itself when it is already absolute, else the directory and the path joined by one separator. When the
current directory cannot be read, `path` itself (std.path throws; Java's `getAbsolutePath` never does).
+/
package(flint) string absolutePath(string path) nothrow
{
    if (path.length == 0)
        return null;
    if (isAbsolute(path))
        return path;
    const base = currentDirectory();
    if (base is null || !isAbsolute(base))
        return path;
    return joinPath(base, path);
}

/++
`parts` joined and normalized, as std.path's `buildNormalizedPath(parts)`: a rooted part starts the path again
(on Windows, one rooted without a drive keeps the drive); separators are collapsed (to `\` on Windows); `.`
segments are dropped; `..` removes the segment before it, is dropped at a root, and stays at the start of a
relative path; a trailing separator is dropped. Empty input gives "", a path that normalizes away gives ".".
+/
package(flint) string normalizedPath(scope const(char)[][] parts...) pure nothrow
{
    const joined = joinedParts(parts);
    if (joined.length == 0)
        return "";
    const root = rootOf(joined);
    string result = root;
    const rest = root.length < joined.length ? joined[root.length .. $] : null;
    foreach (i, segment; resolvedSegments(rest, root.length != 0))
        result ~= i == 0 ? segment : separator ~ segment;
    return result.length ? result : ".";
}

// std.path's chainPath: each rooted part starts the path again.
private string joinedParts(scope const(char)[][] parts) pure nothrow
{
    string joined;
    foreach (part; parts)
    {
        if (part.length == 0)
            continue;
        joined = joined.length == 0 || isAbsolute(part) ? part.idup : joinPath(joined, part.idup);
    }
    return joined;
}

// The segments of `path` (after its root) with `.` dropped and `..` resolved, as std.path's asNormalizedPath.
private string[] resolvedSegments(string path, bool rooted) pure nothrow
{
    string[] segments;
    size_t start;
    foreach (i; 0 .. path.length + 1)
    {
        if (i < path.length && !isSeparator(path[i]))
            continue;
        const segment = path[start .. i];
        start = i + 1;
        if (segment.length == 0 || segment == ".")
            continue;
        if (segment != "..")
            segments ~= segment;
        else if (segments.length && segments[$ - 1] != "..")
            segments = segments[0 .. $ - 1];
        else if (!rooted)
            segments ~= segment;
    }
    return segments;
}

version (Windows)
{
    private enum char separator = '\\';

    private bool isSeparator(char c) pure nothrow @nogc
    {
        return c == '\\' || c == '/';
    }

    // std.path's root of a normalized path: `C:\`, `C:` (drive-relative), `\` (rooted), `\\server\share\`, or none.
    private string rootOf(string path) pure nothrow
    {
        if (path.length >= 2 && path[1] == ':')
            return path.length >= 3 && isSeparator(path[2]) ? path[0 .. 2] ~ separator : path[0 .. 2];
        if (path.length >= 3 && isAbsolute(path))
        {
            const length = rootLength(path);
            string root = "\\\\";
            foreach (c; path[2 .. length])
                root ~= isSeparator(c) ? separator : c;
            return isSeparator(root[$ - 1]) ? root : root ~ separator;
        }
        return path.length && isSeparator(path[0]) ? [separator] : "";
    }

    // std.path: a drive root (`C:\`) or a UNC path (`\\server`).
    private bool isAbsolute(scope const(char)[] path) pure nothrow @nogc
    {
        return path.length >= 3 && ((path[1] == ':' && isSeparator(path[2]))
                || (isSeparator(path[0]) && isSeparator(path[1]) && !isSeparator(path[2])));
    }

    // std.path's rootName length for an absolute path: `C:\`, or `\\server\share`.
    private size_t rootLength(scope const(char)[] path) pure nothrow @nogc
    {
        if (path[1] == ':')
            return 3;
        size_t i = 3;
        while (i < path.length && !isSeparator(path[i]))
            i++;
        if (i < path.length)
        {
            size_t j = i + 1;
            while (j < path.length && isSeparator(path[j]))
                j++;
            if (j < path.length)
            {
                while (j < path.length && !isSeparator(path[j]))
                    j++;
                i = j;
            }
        }
        return i;
    }

    // std.path's chainPath(base, path) for an absolute base and a relative path: a path rooted without a drive
    // (`\x`) keeps only the base's root.
    private string joinPath(string base, string path) pure nothrow
    {
        size_t keep = base.length;
        if (isSeparator(path[0]))
        {
            keep = rootLength(base);
            if (keep > 0 && isSeparator(base[keep - 1]))
                keep--;
            return base[0 .. keep] ~ path;
        }
        return isSeparator(base[$ - 1]) ? base ~ path : base ~ separator ~ path;
    }
}
else
{
    private enum char separator = '/';

    private bool isSeparator(char c) pure nothrow @nogc
    {
        return c == '/';
    }

    private bool isAbsolute(scope const(char)[] path) pure nothrow @nogc
    {
        return path.length != 0 && path[0] == '/';
    }

    // The root of a path: "/" when it is absolute.
    private string rootOf(string path) pure nothrow
    {
        return isAbsolute(path) ? "/" : "";
    }

    private string joinPath(string base, string path) pure nothrow
    {
        return base[$ - 1] == '/' ? base ~ path : base ~ '/' ~ path;
    }
}

private bool holdsNul(scope const(char)[] text) pure nothrow @nogc
{
    foreach (c; text)
        if (c == '\0')
            return true;
    return false;
}

private immutable(char)[] nulTerminated(scope const(char)[] text) pure nothrow
{
    return (text ~ '\0').idup;
}

version (Posix) unittest
{
    import std.file : getcwd, mkdir, remove, rmdir, tempDir, write;
    import std.process : environment;

    // Environment, positive: set, empty (not the default) and listed once.
    environment["FLINT_HOST_TEST"] = "a=b";
    environment["FLINT_HOST_EMPTY"] = "";
    scope (exit)
    {
        environment.remove("FLINT_HOST_TEST");
        environment.remove("FLINT_HOST_EMPTY");
    }
    assert(environmentVariable("FLINT_HOST_TEST") == "a=b");
    const empty = environmentVariable("FLINT_HOST_EMPTY", "fallback");
    assert(empty !is null && empty.length == 0);
    size_t seen;
    foreach (entry; environmentEntries())
        seen += entry.name == "FLINT_HOST_TEST" && entry.value == "a=b";
    assert(seen == 1);
    // Environment, negative: unset, empty or NUL-holding names give the default.
    assert(environmentVariable("FLINT_HOST_UNSET_EVER") is null);
    assert(environmentVariable("FLINT_HOST_UNSET_EVER", "d") == "d");
    assert(environmentVariable("", "d") == "d" && environmentVariable("FLINT_HOST_TEST\0x", "d") == "d");

    // Files, positive: facts, bytes (larger than the first buffer) and an empty file.
    const directory = tempDir ~ "/flint-host-test";
    mkdir(directory);
    const path = directory ~ "/data.bin";
    const blank = directory ~ "/empty.txt";
    auto content = new ubyte[](70_000);
    foreach (i, ref b; content)
        b = cast(ubyte)(i * 7);
    write(path, content);
    write(blank, "");
    scope (exit)
    {
        remove(path);
        remove(blank);
        rmdir(directory);
    }
    const facts = fileFacts(path);
    assert(facts.exists && facts.regular && !facts.directory && facts.size == content.length);
    assert(fileFacts(directory).directory && !fileFacts(directory).regular);
    assert(modifiedMillis(facts) % 1000 == 0 && modifiedMillis(facts) > 1_767_225_600_000);
    FileError error;
    assert(readFile(path, error) == content && error == FileError.none);
    const none = readFile(blank, error);
    assert(none !is null && none.length == 0 && error == FileError.none);
    // Files, negative: missing, a directory, empty or NUL-holding paths.
    assert(!fileFacts(path ~ ".missing").exists && !fileFacts("").exists && !fileFacts(path ~ "\0x").exists);
    assert(readFile(path ~ ".missing", error) is null && error == FileError.notFound);
    assert(describe(error) == "No such file or directory");
    assert(readFile(directory, error) is null && error == FileError.other);
    assert(readFile(path ~ "\0", error) is null && error == FileError.notFound);

    // Paths: std.path's absolutePath and std.file's getcwd.
    assert(currentDirectory() == getcwd());
    assert(absolutePath("") is null && absolutePath("/x/y") == "/x/y");
    assert(absolutePath("a/b") == getcwd() ~ "/a/b");
    assert(joinPath("/", "a") == "/a" && joinPath("/r/", "a") == "/r/a");
    // modifiedMillis truncates toward zero, as SysTime.toUnixTime.
    assert(modifiedMillis(FileFacts(true, true, false, 0, -5_000_000)) == 0);
    assert(modifiedMillis(FileFacts(true, true, false, 0, 15_000_000)) == 1000);
}

version (Posix) unittest
{
    import std.algorithm.sorting : sort;
    import std.conv : to;
    import std.file : dirEntries, mkdir, rmdirRecurse, SpanMode, symlink, tempDir, write;
    import std.process : thisProcessID;

    // Subdirectories, positive: directories and a link to one, not files, a dangling link or `.`/`..`; the same
    // names as std.file's dirEntries/isDir, with and without a trailing separator.
    const root = tempDir ~ "/flint-host-dirs-" ~ thisProcessID.to!string;
    mkdir(root);
    scope (exit)
        rmdirRecurse(root);
    mkdir(root ~ "/b");
    mkdir(root ~ "/a");
    write(root ~ "/file", "x");
    symlink(root ~ "/a", root ~ "/link");
    symlink(root ~ "/gone", root ~ "/dangling");
    FileError error;
    auto paths = subdirectoryPaths(root, error);
    assert(error == FileError.none);
    paths.sort();
    assert(paths == [root ~ "/a", root ~ "/b", root ~ "/link"], paths.to!string);
    string[] expected;
    foreach (entry; dirEntries(root, SpanMode.shallow))
        if (entry.isDir)
            expected ~= entry.name;
    expected.sort();
    assert(paths == expected);
    auto slashed = subdirectoryPaths(root ~ "/", error);
    slashed.sort();
    assert(slashed == paths);
    assert(subdirectoryPaths(root ~ "/b", error).length == 0 && error == FileError.none);
    // Negative: missing, a file, empty or NUL-holding paths.
    assert(subdirectoryPaths(root ~ "/missing", error) is null && error == FileError.notFound);
    assert(subdirectoryPaths(root ~ "/file", error) is null && error == FileError.notFound);
    assert(subdirectoryPaths("", error) is null && error == FileError.notFound);
    assert(subdirectoryPaths(root ~ "\0x", error) is null && error == FileError.notFound);
}

version (Posix) unittest
{
    import std.path : buildNormalizedPath;

    // Normalization, positive: std.path's buildNormalizedPath for one and two parts.
    static immutable string[] paths = [
        "", ".", "..", "/", "//", "a", "a/", "a//b", "./a", "a/.", "a/./b", "a/..", "a/../..",
        "../a", "../../a/b", "/..", "/../a", "/a/../../b", "/a/b/../c/", "a/b/c/../../d",
        "resources/./config/", "x/../y/./z//", "/a/./b/../../c", "./", "a/b/../..", "../", "/./"
    ];
    foreach (path; paths)
        assert(normalizedPath(path) == buildNormalizedPath(path), path);
    foreach (base; ["", "/root", "rel", "/root/", "./w"])
        foreach (path; paths)
            assert(normalizedPath(base, path) == buildNormalizedPath(base, path), base ~ " + " ~ path);
    // Negative: no parts, empty parts.
    assert(normalizedPath() == "" && normalizedPath("", "") == "");
}

version (Posix) unittest
{
    import std.conv : to;
    import std.file : read, readText, remove, tempDir, thisExePath;
    import std.process : thisProcessID;

    // Writes, positive and negative (a missing directory, an empty or NUL-holding path).
    const written = tempDir ~ "/flint-host-write-" ~ thisProcessID.to!string;
    FileError error;
    assert(writeFile(written, cast(const(ubyte)[]) "12 34\n", error) && error == FileError.none);
    assert(readText(written) == "12 34\n");
    assert(writeFile(written, null, error) && read(written).length == 0);
    remove(written);
    assert(!writeFile(written ~ ".missing/x", [1], error) && error == FileError.notFound);
    assert(!writeFile("", [1], error) && !writeFile(written ~ "\0", [1], error));
    // The executable and the process id, as std.file and std.process give them.
    version (linux)
        assert(executablePath() == thisExePath());
    assert(processId() == thisProcessID && processId() > 0);
}
