/// Raw file and process-environment reads for configuration loading, with std.file and std.process semantics.
module flint.config.sys.files;

@safe:

/// Whether `path` names a directory entry; like std.file.exists, a dangling symbolic link exists.
// SAFETY: The path is copied into a NUL-terminated buffer that outlives the C call, and `lstat` writes only
// to the local `stat_t`.
package(flint.config) bool pathExists(string path) @trusted nothrow
{
    import core.sys.posix.sys.stat : lstat, stat_t;

    const terminated = path ~ '\0';
    stat_t status = void;
    return lstat(terminated.ptr, &status) == 0;
}

/// Read at most `limit` bytes with the open, fstat and read sequence of std.file.read; false when any call
/// fails. The descriptor is closed on every path.
// SAFETY: NUL-terminated path outlives `open`; each `read` writes only inside the GC buffer's
// `[size .. min(length, limit)]` window.
package(flint.config) bool readLimited(string path, size_t limit, out string content) @trusted nothrow
{
    import core.sys.posix.fcntl : O_RDONLY, open;
    import core.sys.posix.sys.stat : fstat, stat_t;
    import core.sys.posix.unistd : close, read;

    const terminated = path ~ '\0';
    const fd = open(terminated.ptr, O_RDONLY);
    if (fd == -1)
        return false;
    scope (exit)
        close(fd);
    stat_t status = void;
    if (fstat(fd, &status) != 0)
        return false;
    const wanted = status.st_size ? cast(size_t) status.st_size + 1 : 4096;
    auto buffer = new char[wanted < limit ? wanted : limit];
    size_t size;
    for (;;)
    {
        const window = (buffer.length < limit ? buffer.length : limit) - size;
        const actual = read(fd, buffer.ptr + size, window);
        if (actual == -1)
            return false;
        if (actual == 0)
            break;
        size += actual;
        if (size >= limit)
            break;
        if (size < buffer.length)
            continue;
        buffer.length = size + 16_384;
    }
    content = buffer[0 .. size].idup;
    return true;
}

/// The process environment as std.process.environment.toAA() returns it: each entry copied and split at its
/// first `=`, and the first definition of a repeated name wins.
// SAFETY: `environ` is the C runtime's null-terminated array of NUL-terminated strings, read up to each
// terminator and copied before use.
package(flint.config) @trusted string[string] processEnvironment()
{
    import core.stdc.string : strlen;
    import core.sys.posix.unistd : environ;

    string[string] variables;
    for (size_t index; environ[index]!is null; ++index)
    {
        const definition = environ[index][0 .. strlen(environ[index])].idup;
        size_t equals;
        while (equals < definition.length && definition[equals] != '=')
            ++equals;
        // std.process asserts that every entry has a separator; skip one that does not.
        if (equals == definition.length)
            continue;
        const name = definition[0 .. equals];
        if (name !in variables)
            variables[name] = definition[equals + 1 .. $];
    }
    return variables;
}
