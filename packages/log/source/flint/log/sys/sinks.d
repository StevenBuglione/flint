module flint.log.sys.sinks;

import core.stdc.errno : EACCES, EAGAIN, EINTR, ENOENT, errno;
import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_CREAT, O_NONBLOCK, O_WRONLY, open;
import core.sys.posix.poll : poll;
import core.sys.posix.signal : SIGPIPE, SIG_BLOCK, pthread_sigmask, sigaddset, sigemptyset, sigset_t;
import core.sys.posix.unistd : close, write;
import core.thread : Thread;
import flint.arena : Error, Result, Status;
import flint.log.types : Level;

@safe:

package(flint.log):

struct NativeSink
{
    private int output = -1;
    private int errors = -1;
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
        return Result!NativeSink(NativeSink(descriptor, descriptor));
    }

    const output = open("/proc/self/fd/1", flags);
    if (output < 0)
        return Result!NativeSink(NativeSink.init, Error(ioStatus(errno), "could not open logger stdout"));
    const errors = open("/proc/self/fd/2", flags);
    if (errors < 0)
    {
        const status = ioStatus(errno);
        close(output);
        return Result!NativeSink(NativeSink.init, Error(status, "could not open logger stderr"));
    }
    return Result!NativeSink(NativeSink(output, errors));
}

// SAFETY: The only owner releases each live descriptor once. A file may be shared by both severities.
void closeSink(ref NativeSink sink) @trusted nothrow @nogc
{
    if (sink.output >= 0)
        close(sink.output);
    if (sink.errors >= 0 && sink.errors != sink.output)
        close(sink.errors);
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
    const descriptor = severity == Level.error ? sink.errors : sink.output;
    const count = write(descriptor, bytes.ptr, bytes.length);
    if (count < 0)
        return Result!size_t(0, Error(ioStatus(errno), "logger sink write failed"));
    if (count == 0)
        return Result!size_t(0, Error(Status.ioError, "logger sink made no progress"));
    return Result!size_t(cast(size_t) count);
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
