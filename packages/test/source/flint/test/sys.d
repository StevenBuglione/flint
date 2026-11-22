/// Raw report-file and standard-output writes for the test runner, without std.stdio or std.file.
///
/// The runner is linked into every test executable. Phobos' file and stdio modules pull in std.process,
/// std.socket, std.concurrency and their dependencies through the static Phobos archive, which more than
/// doubles a small test binary; these calls are what the runner actually needs from them.
module flint.test.sys;

@safe:

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

/// Write `line` and a newline to the C standard output stream, as std.stdio.writeln does.
// SAFETY: `fwrite` reads exactly `line.length` bytes from `line.ptr`; `stdout` is the process-wide C stream.
package(flint.test) void writeLine(scope const(char)[] line) @trusted nothrow @nogc
{
    import core.stdc.stdio : fputc, fwrite, stdout;

    fwrite(line.ptr, 1, line.length, stdout);
    fputc('\n', stdout);
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
