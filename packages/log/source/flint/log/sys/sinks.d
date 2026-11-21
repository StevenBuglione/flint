module flint.log.sys.sinks;

import core.stdc.errno : EACCES, EAGAIN, EINTR, ENOENT, ENOTSOCK, errno;
import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_CREAT, O_NONBLOCK, O_WRONLY, fcntl, open;
import core.sys.posix.poll : POLLOUT, poll, pollfd;
import core.sys.posix.signal : SIGPIPE, SIG_BLOCK, pthread_sigmask, sigaddset, sigemptyset, sigset_t;
import core.sys.posix.sys.socket : send;
import core.sys.posix.unistd : close, write;
import core.thread : Thread;
import flint.arena : Error, Result, Status;
import flint.log.types : Level;

@safe:

version (linux)
{
    import core.sys.linux.sys.socket : MSG_DONTWAIT;

    // The Linux fcntl UAPI exposes this command even where druntime omits the spelling.
    private enum F_DUPFD_CLOEXEC = 1030;
}
else
{
    import core.sys.posix.fcntl : F_DUPFD_CLOEXEC;
    import core.sys.posix.sys.socket : MSG_DONTWAIT;
}

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
    if (code == EAGAIN || code == EINTR)
        return Status.unavailable;
    if (code == EACCES)
        return Status.permissionDenied;
    if (code == ENOENT)
        return Status.notFound;
    return Status.ioError;
}

// SAFETY: open only borrows the validated terminated path. The sink owns both returned descriptors.
@trusted Result!NativeSink openSink(string path)
{
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

// SAFETY: Both operations return an owned descriptor. The proc path is terminated and borrowed only during open.
private Stream openStream(string path, int inherited, int flags) @trusted nothrow @nogc
{
    const descriptor = open(path.ptr, flags);
    if (descriptor >= 0)
        return Stream(descriptor);
    return Stream(fcntl(inherited, F_DUPFD_CLOEXEC, 3), true);
}

// SAFETY: The only owner releases each live descriptor once. A file may be shared by both severities.
void closeSink(ref NativeSink sink) @trusted nothrow @nogc
{
    if (sink.output.descriptor >= 0)
        close(sink.output.descriptor);
    if (sink.errors.descriptor >= 0 && sink.errors.descriptor != sink.output.descriptor)
        close(sink.errors.descriptor);
    sink = NativeSink.init;
}

// SAFETY: The mask affects only this sink worker, and local storage is not retained.
Status protectSink() @trusted nothrow @nogc
{
    sigset_t blocked;
    if (sigemptyset(&blocked) != 0 || sigaddset(&blocked, SIGPIPE) != 0)
        return Status.ioError;
    return pthread_sigmask(SIG_BLOCK, &blocked, null) == 0 ? Status.ok : Status.ioError;
}

// SAFETY: write reads at most the borrowed bytes and returns before the consumer can reuse its buffer.
Result!size_t push(ref const NativeSink sink, Level severity, scope const(char)[] bytes) @trusted nothrow @nogc
{
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
    poll(null, 0, 1);
}

// SAFETY: The new worker owns a GC-retained delegate with a safe nonthrowing entry.
@trusted Thread startConsumer(void delegate() @safe nothrow @nogc entry)
{
    auto worker = new Thread(entry);
    worker.isDaemon = true;
    return worker.start();
}

// SAFETY: One external caller joins a previously started worker. The worker cannot join itself.
@trusted Throwable joinConsumer(Thread worker) nothrow
{
    try
        return worker.join(false);
    catch (Exception failure)
        return failure;
}

@("a missing proc view uses owned close-on-exec duplicates of inherited streams")
@system unittest
{
    import core.sys.posix.fcntl : FD_CLOEXEC, F_GETFD, F_GETFL;
    import core.sys.posix.unistd : pipe, read;

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
