/// Scoped Linux socket I/O and numeric thread identity for the benchmark.
module flint_bench_gc.sys.loopback;

import std.stdio : stderr;

version (linux)
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.sys.socket : MSG_NOSIGNAL, recv, send;
}
else
    static assert(0, "the hot-GC transport probe targets Linux");

extern (C) private int gettid() nothrow @nogc;

@safe:

/// Read the current worker's Linux thread ID.
// SAFETY: Linux reports the numeric identity of the current kernel thread. No state or pointer escapes.
@trusted int linuxThreadId() nothrow @nogc
{
    return gettid();
}

/// Write the complete request on one preconfigured blocking socket.
// SAFETY: send synchronously borrows the provided slice for at most its length. The caller
// retains the connected fd until all operations finish. Syscalls do not invoke D callbacks.
@trusted bool sendAll(int fd, scope const(char)[] pending) nothrow @nogc
{
    while (pending.length)
    {
        const count = send(fd, pending.ptr, pending.length, MSG_NOSIGNAL);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return false;
        pending = pending[count .. $];
    }
    return true;
}

/// Read a fixed-size response without allocating or buffering any other connection.
// SAFETY: recv synchronously borrows the writable slice until it returns. The caller holds an
// exclusive view of the writable bytes and retains the fd. Syscalls cannot unwind D exceptions.
@trusted bool receiveAll(int fd, scope char[] pending) nothrow @nogc
{
    while (pending.length)
    {
        const count = recv(fd, pending.ptr, pending.length, 0);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return false;
        pending = pending[count .. $];
    }
    return true;
}

/// Write failure diagnostics outside the sample interval.
// SAFETY: stderr is the process-owned standard stream. The coordinator invokes it after
// a failed operation. The immutable message is kept alive through the synchronous write.
@trusted void diagnostic(string message)
{
    stderr.writeln(message);
}
