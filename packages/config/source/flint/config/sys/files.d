/// Raw file and process-environment reads for configuration loading, with std.file and std.process semantics.
module flint.config.sys.files;

@safe:

version (Windows)
{
    import core.sys.windows.winbase : CloseHandle, CreateFileW, FILE_FLAG_SEQUENTIAL_SCAN, FreeEnvironmentStringsW,
        GetEnvironmentStringsW, GetFileAttributesW, GetFileSizeEx, INVALID_HANDLE_VALUE, OPEN_EXISTING, ReadFile;
    import core.sys.windows.winnt : FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, GENERIC_READ,
        INVALID_FILE_ATTRIBUTES, LARGE_INTEGER;

    /// Whether `path` names a directory entry, as std.file.exists decides it on Windows: the attributes of the
    /// entry itself, so a dangling symbolic link exists.
    // SAFETY: The UTF-16 copy is NUL-terminated and outlives the call, which reads only the path.
    package(flint.config) bool pathExists(string path) @trusted nothrow
    {
        const wide = widePath(path);
        return wide !is null && GetFileAttributesW(wide) != INVALID_FILE_ATTRIBUTES;
    }

    /// Read at most `limit` bytes with the CreateFileW, GetFileSizeEx and ReadFile sequence of std.file.read;
    /// false when any call fails. The handle is closed on every path.
    // SAFETY: The NUL-terminated UTF-16 path outlives `CreateFileW`; the size query writes only the local length,
    // and the handle stays open while readAll reads it.
    package(flint.config) bool readLimited(string path, size_t limit, out string content) @trusted nothrow
    {
        const wide = widePath(path);
        if (wide is null)
            return false;
        auto handle = CreateFileW(wide, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, null);
        if (handle == INVALID_HANDLE_VALUE)
            return false;
        scope (exit)
            CloseHandle(handle);
        LARGE_INTEGER length;
        if (!GetFileSizeEx(handle, &length) || length.QuadPart < 0)
            return false;
        const wanted = length.QuadPart ? cast(size_t) length.QuadPart + 1 : 4096;
        return readAll(handle, wanted < limit ? wanted : limit, limit, content);
    }

    // Read until end of file or `limit` bytes into a buffer that starts at `initial` bytes and grows by 16 KiB.
    // SAFETY: Each `ReadFile` writes only inside the GC buffer's `[size .. min(length, limit)]` window.
    private bool readAll(void* handle, size_t initial, size_t limit, out string content) @trusted nothrow
    {
        auto buffer = new char[initial];
        size_t size;
        for (;;)
        {
            size_t window = (buffer.length < limit ? buffer.length : limit) - size;
            if (window > uint.max)
                window = uint.max;
            uint actual;
            if (!ReadFile(handle, buffer.ptr + size, cast(uint) window, &actual, null))
                return false;
            size += actual;
            if (actual == 0 || size >= limit)
                break;
            if (size == buffer.length)
                buffer.length = size + 16_384;
        }
        content = buffer[0 .. size].idup;
        return true;
    }

    /// The process environment as std.process.environment.toAA() returns it on Windows: each entry of the
    /// environment block converted to UTF-8 and split at the first `=` after its first character, entries with
    /// an empty name (the per-drive working directories) skipped, and the first definition of a name winning.
    // SAFETY: The environment block is a sequence of NUL-terminated UTF-16 strings ended by an empty one; it is
    // read only up to that terminator, copied, and released before returning.
    package(flint.config) @trusted string[string] processEnvironment()
    {
        import std.utf : toUTF8;

        string[string] variables;
        auto block = GetEnvironmentStringsW();
        if (block is null)
            return variables;
        scope (exit)
            FreeEnvironmentStringsW(block);
        for (size_t start; block[start] != 0;)
        {
            size_t end = start;
            while (block[end] != 0)
                ++end;
            const entry = block[start .. end];
            start = end + 1;
            size_t equals = 1;
            while (equals < entry.length && entry[equals] != '=')
                ++equals;
            if (equals >= entry.length || entry[0] == '=')
                continue;
            try
            {
                const name = toUTF8(entry[0 .. equals]);
                if (name !in variables)
                    variables[name] = toUTF8(entry[equals + 1 .. $]);
            }
            catch (Exception)
                continue;
        }
        return variables;
    }

    // A NUL-terminated UTF-16 copy of a UTF-8 path, or null when the path is not valid UTF-8 or contains NUL.
    private const(wchar)* widePath(string path) nothrow
    {
        import std.utf : toUTF16z;

        foreach (character; path)
            if (character == 0)
                return null;
        try
            return toUTF16z(path);
        catch (Exception)
            return null;
    }
}
else
{

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
}
