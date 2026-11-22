module flint.log.sys.sinks;

// Only the declaration types are imported at module scope. OS bindings are local to the
// functions that use them, so importing flint.log does not analyze them.
import flint.arena : Error, Result, Status;
import flint.log.types : Level;

@safe:

package(flint.log):

struct NativeSink
{
    private Stream output;
    private Stream errors;
}

private struct Stream
{
    int descriptor = -1;
    bool inherited;
}

private Status ioStatus(int code) pure nothrow @nogc
{
    import core.stdc.errno : EACCES, EAGAIN, EINTR, ENOENT;

    if (code == EAGAIN || code == EINTR)
        return Status.unavailable;
    if (code == EACCES)
        return Status.permissionDenied;
    if (code == ENOENT)
        return Status.notFound;
    return Status.ioError;
}

// SAFETY: fcntl only duplicates a descriptor number and returns an owned descriptor or -1.
private int duplicate(int descriptor) @trusted nothrow @nogc
{
    import core.sys.posix.fcntl : fcntl;

    version (linux)
        enum command = 1030; // F_DUPFD_CLOEXEC in the Linux UAPI, even where druntime omits it.
    else
        import core.sys.posix.fcntl : command = F_DUPFD_CLOEXEC;

    return fcntl(descriptor, command, 3);
}

// SAFETY: open only borrows the validated terminated path. The sink owns both returned descriptors.
@trusted Result!NativeSink openSink(string path)
{
    import core.stdc.errno : errno;
    import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_CREAT, O_NONBLOCK, O_WRONLY, open;
    import core.sys.posix.unistd : close;

    enum flags = O_WRONLY | O_APPEND | O_NONBLOCK | O_CLOEXEC;
    if (path.length != 0)
    {
        const terminated = path ~ "\0";
        const descriptor = open(terminated.ptr, flags | O_CREAT, 0x180);
        if (descriptor < 0)
            return Result!NativeSink(NativeSink.init, Error(ioStatus(errno), "could not open logger file"));
        return Result!NativeSink(NativeSink(Stream(descriptor), Stream(descriptor)));
    }

    const output = openStream("/proc/self/fd/1", 1, flags);
    if (output.descriptor < 0)
        return Result!NativeSink(NativeSink.init, Error(ioStatus(errno), "could not open logger stdout"));
    const errors = openStream("/proc/self/fd/2", 2, flags);
    if (errors.descriptor < 0)
    {
        const status = ioStatus(errno);
        close(output.descriptor);
        return Result!NativeSink(NativeSink.init, Error(status, "could not open logger stderr"));
    }
    return Result!NativeSink(NativeSink(output, errors));
}

// A seekable stream, such as a regular file opened by `> file`, keeps the caller's description: an
// independent description would have its own offset, and the two writers would overwrite each other.
// SAFETY: Every operation returns an owned descriptor. The proc path is terminated and borrowed only during open.
private Stream openStream(string path, int inherited, int flags) @trusted nothrow @nogc
{
    import core.stdc.stdio : SEEK_CUR;
    import core.sys.posix.fcntl : open;
    import core.sys.posix.unistd : lseek;

    if (lseek(inherited, 0, SEEK_CUR) >= 0)
        return Stream(duplicate(inherited));
    const descriptor = open(path.ptr, flags);
    if (descriptor >= 0)
        return Stream(descriptor);
    return Stream(duplicate(inherited), true);
}

// SAFETY: The only owner releases each live descriptor once. A file may be shared by both severities.
void closeSink(ref NativeSink sink) @trusted nothrow @nogc
{
    import core.sys.posix.unistd : close;

    if (sink.output.descriptor >= 0)
        close(sink.output.descriptor);
    if (sink.errors.descriptor >= 0 && sink.errors.descriptor != sink.output.descriptor)
        close(sink.errors.descriptor);
    sink = NativeSink.init;
}

// SAFETY: The mask affects only this sink worker, and local storage is not retained.
Status protectSink() @trusted nothrow @nogc
{
    import core.sys.posix.signal : SIGPIPE, SIG_BLOCK, pthread_sigmask, sigaddset, sigemptyset, sigset_t;

    sigset_t blocked;
    if (sigemptyset(&blocked) != 0 || sigaddset(&blocked, SIGPIPE) != 0)
        return Status.ioError;
    return pthread_sigmask(SIG_BLOCK, &blocked, null) == 0 ? Status.ok : Status.ioError;
}

// SAFETY: write reads at most the borrowed bytes and returns before the consumer can reuse its buffer.
Result!size_t push(ref const NativeSink sink, Level severity, scope const(char)[] bytes) @trusted nothrow @nogc
{
    import core.stdc.errno : errno;
    import core.sys.posix.unistd : write;

    const stream = severity == Level.error ? sink.errors : sink.output;
    const count = stream.inherited ? writeInherited(stream.descriptor,
            bytes) : write(stream.descriptor, bytes.ptr, bytes.length);
    if (count < 0)
        return Result!size_t(0, Error(ioStatus(errno), "logger sink write failed"));
    if (count == 0)
        return Result!size_t(0, Error(Status.ioError, "logger sink made no progress"));
    return Result!size_t(cast(size_t) count);
}

// SAFETY: Native I/O borrows a bounded byte slice and poll writes only to a local item. Socket sends
// are nonblocking per call. A blocking inherited file uses the consumer's retained buffer until it returns.
private ptrdiff_t writeInherited(int fd, scope const(char)[] bytes) @trusted nothrow @nogc
{
    import core.stdc.errno : EAGAIN, ENOTSOCK, errno;
    import core.sys.posix.poll : POLLOUT, poll, pollfd;
    import core.sys.posix.sys.socket : send;
    import core.sys.posix.unistd : write;

    version (linux)
        import core.sys.linux.sys.socket : MSG_DONTWAIT;
    else
        import core.sys.posix.sys.socket : MSG_DONTWAIT;

    const sent = send(fd, bytes.ptr, bytes.length, MSG_DONTWAIT);
    if (sent >= 0 || errno != ENOTSOCK)
        return sent;
    pollfd ready = pollfd(fd, POLLOUT, 0);
    const count = poll(&ready, 1, 0);
    if (count == 0)
        errno = EAGAIN;
    if (count <= 0)
        return -1;
    enum maxChunk = 4096;
    const length = bytes.length < maxChunk ? bytes.length : maxChunk;
    return write(fd, bytes.ptr, length);
}

// SAFETY: poll with a null descriptor array only sleeps on the calling thread.
void pauseConsumer() @trusted nothrow @nogc
{
    import core.sys.posix.poll : poll;

    poll(null, 0, 1);
}

version (linux)
{
    version (X86_64)
        private enum futexCall = 202;
    else version (AArch64)
        private enum futexCall = 98;
    else version (RISCV64)
        private enum futexCall = 98;
}

// SAFETY: The kernel compares the aligned 32-bit word with expected and sleeps at most nanos.
// It reads the word only during the call and retains neither address. Without a futex this sleeps.
void park(ref shared uint word, uint expected, long nanos) @trusted nothrow @nogc
{
    static if (is(typeof(futexCall)))
    {
        import core.sys.linux.unistd : syscall;
        import core.sys.posix.time : timespec;

        enum waitPrivate = 128; // FUTEX_WAIT | FUTEX_PRIVATE_FLAG
        timespec limit;
        limit.tv_sec = nanos / 1_000_000_000;
        limit.tv_nsec = nanos % 1_000_000_000;
        // EINTR, EAGAIN and ETIMEDOUT all return to a caller that rechecks its condition.
        syscall(futexCall, cast(void*)&word, waitPrivate, expected, &limit, null, 0);
    }
    else
        pauseConsumer();
}

// SAFETY: The kernel uses the word address only as a key for waking its current waiters.
void wake(ref shared uint word) @trusted nothrow @nogc
{
    static if (is(typeof(futexCall)))
    {
        import core.sys.linux.unistd : syscall;

        enum wakePrivate = 129; // FUTEX_WAKE | FUTEX_PRIVATE_FLAG
        syscall(futexCall, cast(void*)&word, wakePrivate, int.max, null, null, 0);
    }
}

// SAFETY: The new worker owns a GC-retained delegate with a safe nonthrowing entry. The handle is
// returned as Object so that declarations naming it do not import the thread runtime.
@trusted Object startConsumer(void delegate() @safe nothrow @nogc entry)
{
    import core.thread : Thread;

    auto worker = new Thread(entry);
    worker.isDaemon = true;
    return worker.start();
}

// SAFETY: One external caller joins a previously started worker. The worker cannot join itself.
@trusted Throwable joinConsumer(Object handle) nothrow
{
    import core.thread : Thread;

    auto worker = cast(Thread) handle;
    if (worker is null)
        return null;
    try
        return worker.join(false);
    catch (Exception failure)
        return failure;
}

@("a missing proc view uses owned close-on-exec duplicates of inherited streams")
@system unittest
{
    import core.sys.posix.fcntl : FD_CLOEXEC, F_GETFD, F_GETFL, O_WRONLY, fcntl;
    import core.sys.posix.unistd : close, pipe, read;

    int[2] ends;
    assert(pipe(ends) == 0);
    scope (exit)
    {
        close(ends[0]);
        close(ends[1]);
    }
    const before = fcntl(ends[1], F_GETFL);
    const stream = openStream("/proc/self/flint-missing-descriptor", ends[1], O_WRONLY);
    assert(stream.inherited && stream.descriptor >= 3 && stream.descriptor != ends[1]);
    scope (exit)
        close(stream.descriptor);
    assert((fcntl(stream.descriptor, F_GETFD) & FD_CLOEXEC) != 0);
    assert(fcntl(ends[1], F_GETFL) == before);
    assert(writeInherited(stream.descriptor, "test") == 4);
    char[4] bytes;
    assert(read(ends[0], bytes.ptr, bytes.length) == 4 && bytes[] == "test");
}

// druntime 2.113/2.114 declares pread for glibc and the BSDs but not for musl, whose libc exports it.
version (CRuntime_Musl)
{
    import core.sys.posix.sys.types : off_t, ssize_t;

    pragma(mangle, "pread") private extern (C) ssize_t muslPread(int, void*, size_t, off_t) nothrow @nogc @system;
}

@("a regular-file standard stream shares the offset of the inherited description")
@system unittest
{
    import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_NONBLOCK, O_WRONLY;
    import core.sys.posix.stdlib : mkstemp;
    import core.sys.posix.unistd : close, unlink, write;

    version (CRuntime_Musl)
        alias pread = muslPread;
    else
        import core.sys.posix.unistd : pread;

    char[32] name = "/tmp/flint-log-offset-XXXXXX\0";
    const file = mkstemp(name.ptr);
    assert(file >= 0);
    scope (exit)
    {
        unlink(name.ptr);
        close(file);
    }
    char[24] proc = "/proc/self/fd/";
    size_t length = 14;
    char[10] digits;
    size_t count;
    for (uint rest = file; rest != 0 || count == 0; rest /= 10)
        digits[count++] = cast(char)('0' + rest % 10);
    foreach_reverse (digit; digits[0 .. count])
        proc[length++] = digit;
    proc[length] = '\0';

    // The shell opens `> file` without O_APPEND. The logger and the caller must not overwrite each other.
    const stream = openStream(cast(string) proc[0 .. length], file, O_WRONLY | O_APPEND | O_NONBLOCK | O_CLOEXEC);
    assert(stream.descriptor >= 0 && stream.descriptor != file);
    scope (exit)
        close(stream.descriptor);
    const sink = NativeSink(stream, stream);
    assert(push(sink, Level.info, "log\n").value == 4);
    assert(write(file, "out\n".ptr, 4) == 4);
    char[16] bytes;
    assert(pread(file, bytes.ptr, bytes.length, 0) == 8 && bytes[0 .. 8] == "log\nout\n");
}
