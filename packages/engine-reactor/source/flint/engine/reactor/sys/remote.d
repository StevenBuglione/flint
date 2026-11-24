/// Fiber wakes posted from other threads to one worker loop (`Reactor.wakeFromAnyThread`).
module flint.engine.reactor.sys.remote;

import core.sync.mutex : Mutex;
import flint.arena : Status;
import flint.engine.reactor.types : TaskWaker;

@safe:

version (Posix)
{
    import core.sys.posix.fcntl : F_GETFL, F_SETFD, F_SETFL, FD_CLOEXEC, O_NONBLOCK, fcntl;
    import core.sys.posix.unistd : close, pipe, read, write;
}

/// A bounded list of task handles other threads queued for one worker, and the descriptor that becomes readable
/// when the list gains one. The worker watches the descriptor, takes the list and applies each handle as its own
/// `wake`, which rejects a handle whose task ended. A full list refuses the wake; the waiter's own deadline then
/// resumes it, so a wake is late at worst, never lost to a fiber that re-checks its condition.
package(flint.engine.reactor) final class RemoteWakes
{
    private Mutex lock;
    private TaskWaker[] pending;
    private size_t count;
    private int reader = -1;
    private int writer = -1;

    /// Reserve room for `capacity` queued wakes.
    this(size_t capacity)
    {
        lock = new Mutex;
        pending = new TaskWaker[capacity];
    }

    /// Open the signal. Without one (Windows, ADR-026) every `post` is refused.
    Status open() nothrow @nogc
    {
        return openSignal(reader, writer) ? Status.ok : Status.ioError;
    }

    /// Close the signal. A thread that posts afterwards is refused rather than writing to a reused descriptor.
    /// Repeated calls do nothing.
    void close() nothrow @nogc
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        closeSignal(reader);
        closeSignal(writer);
    }

    /// The descriptor the worker watches, or -1 where signals are unsupported.
    int signal() const nothrow @nogc
    {
        return reader;
    }

    /// The list's capacity, which the worker's `take` buffer matches.
    size_t capacity() const nothrow @nogc
    {
        return pending.length;
    }

    /// Queue `waker` and signal the worker. False when there is no signal or the list is full.
    bool post(TaskWaker waker) nothrow @nogc
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        if (writer < 0 || count == pending.length)
            return false;
        pending[count++] = waker;
        raiseSignal(writer);
        return true;
    }

    /// Consume the signal, then move every queued wake into `into`, which holds `capacity` handles. A wake
    /// posted after the signal was consumed raises it again, so the worker's next pass takes it.
    size_t take(scope TaskWaker[] into) nothrow @nogc
    {
        drainSignal(reader);
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        const taken = count < into.length ? count : into.length;
        into[0 .. taken] = pending[0 .. taken];
        // `into` matches the capacity, so nothing is left behind; a smaller buffer keeps the rest in order.
        foreach (index; taken .. count)
            pending[index - taken] = pending[index];
        count -= taken;
        return taken;
    }
}

// SAFETY: pipe writes two descriptors into a local array; fcntl only changes flags of those descriptors.
private bool openSignal(ref int reader, ref int writer) @trusted nothrow @nogc
{
    version (Posix)
    {
        int[2] ends;
        if (pipe(ends) != 0)
            return false;
        reader = ends[0];
        writer = ends[1];
        foreach (end; ends)
        {
            const flags = fcntl(end, F_GETFL);
            if (flags < 0 || fcntl(end, F_SETFL, flags | O_NONBLOCK) != 0 || fcntl(end, F_SETFD, FD_CLOEXEC) != 0)
                return false;
        }
        return true;
    }
    else
        return true;
}

// SAFETY: Closes a descriptor this list opened and marks it closed so it is never closed twice.
private void closeSignal(ref int descriptor) @trusted nothrow @nogc
{
    version (Posix)
        if (descriptor >= 0)
            close(descriptor);
    descriptor = -1;
}

// SAFETY: Writes one byte from a local to the list's nonblocking pipe. A full pipe already signals.
private void raiseSignal(int descriptor) @trusted nothrow @nogc
{
    version (Posix)
    {
        ubyte one = 1;
        cast(void) write(descriptor, &one, 1);
    }
}

// SAFETY: Reads into a bounded local buffer from the list's nonblocking pipe until it is empty.
private void drainSignal(int descriptor) @trusted nothrow @nogc
{
    version (Posix)
    {
        if (descriptor < 0)
            return;
        ubyte[64] sink;
        while (read(descriptor, sink.ptr, sink.length) > 0)
        {
        }
    }
}
