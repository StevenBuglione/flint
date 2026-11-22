/// The few POSIX calls flint needs that druntime does not expose as @safe.
module flint_tool.sys.posix;

@safe:

/// Replace this process with `argv` run in `directory`. Returns only on failure, with errno.
int replaceProcess(string executable, scope const(string)[] argv, string directory)
{
    import std.string : toStringz;

    const(char)*[] terminated;
    foreach (argument; argv)
        terminated ~= toStringz(argument);
    terminated ~= null;
    return execute(toStringz(executable), terminated, directory.length == 0 ? null : toStringz(directory));
}

// SAFETY: every pointer is a NUL-terminated GC copy kept alive by the caller's frame for the whole call, and
// argv ends with the null sentinel execv requires; on success the process image is replaced and nothing returns.
private int execute(const(char)* executable, scope const(char)*[] argv, const(char)* directory) @trusted nothrow
{
    import core.stdc.errno : errno;
    import core.sys.posix.unistd : chdir, execv;

    if (directory !is null && chdir(directory) != 0)
        return errno;
    execv(executable, argv.ptr);
    return errno;
}

/// Whether another process holds an exclusive flock on `path` (the compile server's liveness lock).
bool lockHeld(string path)
{
    import std.string : toStringz;

    return probeLock(toStringz(path));
}

version (OSX) private extern (C) int flock(int descriptor, int operation) @system nothrow @nogc;

// SAFETY: the path is a NUL-terminated GC copy; the descriptor is owned locally, released with LOCK_UN when the
// probe acquired it, and always closed before returning.
private bool probeLock(const(char)* path) @trusted nothrow
{
    import core.sys.posix.fcntl : O_RDONLY, open;
    import core.sys.posix.unistd : close;

    version (OSX)
    {
        // <sys/fcntl.h> and <sys/file.h>; druntime declares neither for Darwin.
        enum O_CLOEXEC = 0x0100_0000;
        enum LOCK_EX = 2, LOCK_NB = 4, LOCK_UN = 8;
    }
    else
    {
        import core.sys.posix.fcntl : O_CLOEXEC;
        import core.sys.linux.sys.file : LOCK_EX, LOCK_NB, LOCK_UN, flock;
    }

    const fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    scope (exit)
        close(fd);
    if (flock(fd, LOCK_EX | LOCK_NB) == 0)
    {
        cast(void) flock(fd, LOCK_UN);
        return false;
    }
    return true;
}

/// Send `signal` to the process group led by `pid`, falling back to the process itself.
bool signalProcessGroup(int pid, int signal)
{
    return pid > 1 && deliver(pid, signal);
}

// SAFETY: kill takes only integers; pid is checked by the caller to name neither init nor every process.
private bool deliver(int pid, int signal) @trusted nothrow @nogc
{
    import core.sys.posix.signal : kill;

    return kill(-pid, signal) == 0 || kill(pid, signal) == 0;
}

/// Whether the process `pid` exists.
bool processAlive(int pid)
{
    return pid > 1 && probeProcess(pid);
}

// SAFETY: signal 0 performs only the existence and permission check; no memory is passed.
private bool probeProcess(int pid) @trusted nothrow @nogc
{
    import core.sys.posix.signal : kill;

    return kill(pid, 0) == 0;
}

/// The first of `names` the dynamic loader can open, or null. Each library is closed again at once.
string loadableLibrary(scope const(string)[] names)
{
    import std.string : toStringz;

    foreach (name; names)
    {
        if (probeLibrary(name.toStringz))
            return name;
    }
    return null;
}

// SAFETY: path is a NUL-terminated GC copy kept alive by the caller; the handle dlopen returns is closed before
// returning and never escapes this function.
private bool probeLibrary(const(char)* path) @trusted nothrow @nogc
{
    import core.sys.posix.dlfcn : RTLD_LAZY, dlclose, dlopen;

    auto handle = dlopen(path, RTLD_LAZY);
    if (handle is null)
        return false;
    dlclose(handle);
    return true;
}

/// Write all of `text` to standard output.
void writeOutput(scope const(char)[] text)
{
    writeAll(1, text);
}

/// Write all of `text` to standard error.
void writeError(scope const(char)[] text)
{
    writeAll(2, text);
}

// SAFETY: write reads at most text.length bytes from the slice, whose memory the caller keeps alive for the
// call; the loop advances only by the count the kernel reports and stops on any error.
private void writeAll(int fd, scope const(char)[] text) @trusted nothrow @nogc
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.unistd : write;

    size_t done;
    while (done < text.length)
    {
        const written = write(fd, text.ptr + done, text.length - done);
        if (written < 0 && errno == EINTR)
            continue;
        if (written <= 0)
            return;
        done += written;
    }
}
