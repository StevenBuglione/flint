/// Raw report-file and standard-output writes for the test runner, without std.stdio or std.file.
///
/// The runner is linked into every test executable. Phobos' file and stdio modules pull in std.process,
/// std.socket, std.concurrency and their dependencies through the static Phobos archive, which more than
/// doubles a small test binary; these calls are what the runner actually needs from them.
module flint.test.sys;

@safe:

version (Windows)
{
    private extern (C) nothrow @nogc
    {
        int _wopen(const(wchar)* path, int flags, ...);
        int _write(int fd, const(void)* buffer, uint count);
        int _close(int fd);
    }

    /// Create `path` exclusively, as `File(path, "wbx")` does, and write all of `content` to it. Returns 0 or
    /// the failing call's `errno`; on a write failure the partly written file is left in place, like std.stdio.
    // SAFETY: The path is converted into a NUL-terminated stack buffer that outlives `_wopen`; each `_write` reads
    // only inside `content[written .. $]`, at most uint.max bytes; the descriptor is closed on every path.
    package(flint.test) int createExclusive(string path, scope const(char)[] content) @trusted nothrow @nogc
    {
        import core.stdc.errno : EILSEQ, ENAMETOOLONG, errno;
        import core.sys.windows.winnls : CP_UTF8, MB_ERR_INVALID_CHARS, MultiByteToWideChar;

        enum int writeOnly = 0x0001, create = 0x0100, truncate = 0x0200, exclusive = 0x0400,
                binary = 0x8000, noInherit = 0x0080, readWrite = 0x0180; // _O_* and _S_IREAD | _S_IWRITE
        wchar[32_768] wide = void; // The longest extended-length path, counting the terminator.
        if (path.length >= wide.length)
            return ENAMETOOLONG;
        int units;
        if (path.length != 0)
        {
            units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.ptr,
                    cast(int) path.length, wide.ptr, cast(int) wide.length - 1);
            if (units == 0)
                return EILSEQ;
        }
        wide[units] = 0;
        const fd = _wopen(wide.ptr, writeOnly | create | exclusive | truncate | binary | noInherit, readWrite);
        if (fd == -1)
            return errno;
        size_t written;
        int failure;
        while (written < content.length)
        {
            const remaining = content.length - written;
            const actual = _write(fd, content.ptr + written, remaining > uint.max ? uint.max : cast(uint) remaining);
            if (actual == -1)
            {
                failure = errno;
                break;
            }
            written += actual;
        }
        if (_close(fd) != 0 && failure == 0)
            failure = errno;
        return failure;
    }

    /// The C library's message for `code`, as std.exception.errnoString formats it.
    // SAFETY: The C runtime's `strerror` returns a NUL-terminated string in a thread-local buffer; it is
    // copied before any other C runtime call on this thread can reuse that buffer.
    package(flint.test) string errorText(int code) @trusted nothrow
    {
        import core.stdc.string : strerror, strlen;

        const text = strerror(code);
        return text is null ? "Unknown error" : text[0 .. strlen(text)].idup;
    }
}
else
{
    /// Create `path` exclusively, as `File(path, "wbx")` does, and write all of `content` to it. Returns 0 or
    /// the failing call's `errno`; on a write failure the partly written file is left in place, like std.stdio.
    // SAFETY: The path is copied into a NUL-terminated buffer that outlives `open`; every `write` reads only
    // inside `content[written .. $]`; the descriptor is closed on every path.
    package(flint.test) int createExclusive(string path, scope const(char)[] content) @trusted nothrow @nogc
    {
        import core.stdc.errno : EINTR, ENAMETOOLONG, errno;
        import core.sys.posix.fcntl : O_CREAT, O_EXCL, O_TRUNC, O_WRONLY, open;
        import core.sys.posix.unistd : close, write;

        version (OSX)
            enum O_CLOEXEC = 0x0100_0000; // <sys/fcntl.h>; druntime omits it for Darwin.
        else
            import core.sys.posix.fcntl : O_CLOEXEC;

        char[4096] stack = void;
        if (path.length >= stack.length)
            return ENAMETOOLONG; // Linux PATH_MAX, 4096, counts the terminator.
        stack[0 .. path.length] = path[];
        stack[path.length] = '\0';
        int fd;
        do
            fd = open(stack.ptr, O_WRONLY | O_CREAT | O_EXCL | O_TRUNC | O_CLOEXEC, 438); // 0666 before umask
        while (fd == -1 && errno == EINTR);
        if (fd == -1)
            return errno;
        size_t written;
        int failure;
        while (written < content.length)
        {
            const actual = write(fd, content.ptr + written, content.length - written);
            if (actual == -1)
            {
                if (errno == EINTR)
                    continue;
                failure = errno;
                break;
            }
            written += actual;
        }
        if (close(fd) != 0 && failure == 0 && errno != EINTR)
            failure = errno;
        return failure;
    }

    /// The C library's message for `code`, as std.exception.errnoString formats it.
    // SAFETY: `strerror_r` writes at most `buffer.length` bytes into `buffer` and yields a NUL-terminated string
    // that is static or inside `buffer`; it is copied before `buffer` goes out of scope.
    package(flint.test) string errorText(int code) @trusted nothrow
    {
        import core.stdc.string : strerror_r, strlen;

        char[256] buffer = 0;
        static if (is(typeof(strerror_r(code, buffer.ptr, buffer.length)) == int))
        {
            if (strerror_r(code, buffer.ptr, buffer.length) != 0)
                return "Unknown error";
            const(char)* text = buffer.ptr;
        }
        else
            const text = strerror_r(code, buffer.ptr, buffer.length);
        return text[0 .. strlen(text)].idup;
    }
}

/// Write `line` and a newline to the C standard output stream, as std.stdio.writeln does.
// SAFETY: `fwrite` reads exactly `line.length` bytes from `line.ptr`; `stdout` is the process-wide C stream.
package(flint.test) void writeLine(scope const(char)[] line) @trusted nothrow @nogc
{
    import core.stdc.stdio : fputc, fwrite, stdout;

    fwrite(line.ptr, 1, line.length, stdout);
    fputc('\n', stdout);
}
