/// An owner loop's doorbell: a descriptor other threads make readable so that a sleeping loop wakes for their
/// remote wakes (`RemoteWaker`). An eventfd on Linux, a nonblocking pipe on other POSIX targets. Windows has no
/// doorbell: its loop checks the pending flag on each pass, within the loop's wait bound.
module flint.engine.reactor.sys.doorbell;

@safe:

version (linux)
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.unistd : close, read, write;

    private extern (C) int eventfd(uint initval, int flags) nothrow @nogc @system;
    private enum int efdNonblock = 0x800; // EFD_NONBLOCK
    private enum int efdCloexec = 0x80000; // EFD_CLOEXEC
}
else version (Posix)
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.fcntl : F_GETFL, F_SETFD, F_SETFL, FD_CLOEXEC, O_NONBLOCK, fcntl;
    import core.sys.posix.unistd : close, pipe, read, write;
}

/// The two ends of a doorbell; on Linux both are the same eventfd. -1 when closed or unsupported.
package(flint.engine.reactor) struct Doorbell
{
    int reader = -1;
    int writer = -1;

    bool valid() const pure nothrow @nogc
    {
        return reader >= 0;
    }
}

// SAFETY: eventfd and pipe only write descriptors into locals; fcntl changes flags of those descriptors only.
package(flint.engine.reactor) bool openDoorbell(out Doorbell bell) @trusted nothrow @nogc
{
    version (linux)
    {
        const descriptor = eventfd(0, efdNonblock | efdCloexec);
        if (descriptor < 0)
            return false;
        bell = Doorbell(descriptor, descriptor);
        return true;
    }
    else version (Posix)
    {
        int[2] ends;
        if (pipe(ends) != 0)
            return false;
        bell = Doorbell(ends[0], ends[1]);
        foreach (end; ends)
        {
            const flags = fcntl(end, F_GETFL);
            if (flags < 0 || fcntl(end, F_SETFL, flags | O_NONBLOCK) != 0 || fcntl(end, F_SETFD, FD_CLOEXEC) != 0)
            {
                closeDoorbell(bell);
                return false;
            }
        }
        return true;
    }
    else
        return true;
}

// A saturated eventfd or full pipe is already readable, so a refused write still leaves the loop signalled.
// SAFETY: Writes one counter increment or byte from a local; the caller keeps the descriptor open (WakeLane.writers).
package(flint.engine.reactor) void ringDoorbell(ref const Doorbell bell) @trusted nothrow @nogc
{
    version (Posix)
    {
        if (bell.writer < 0)
            return;
        version (linux)
        {
            ulong one = 1;
            while (write(bell.writer, &one, one.sizeof) < 0 && errno == EINTR)
            {
            }
        }
        else
        {
            ubyte one = 1;
            while (write(bell.writer, &one, 1) < 0 && errno == EINTR)
            {
            }
        }
    }
}

// SAFETY: Reads into a bounded local buffer from the nonblocking doorbell until it reports empty.
package(flint.engine.reactor) void drainDoorbell(ref const Doorbell bell) @trusted nothrow @nogc
{
    version (Posix)
    {
        if (bell.reader < 0)
            return;
        ulong[8] sink;
        for (;;)
        {
            const count = read(bell.reader, sink.ptr, sink.sizeof);
            if (count > 0)
            {
                // An eventfd read returns the whole counter at once.
                version (linux)
                    return;
                else
                    continue;
            }
            if (count < 0 && errno == EINTR)
                continue;
            return;
        }
    }
}

// SAFETY: Closes descriptors this module opened and marks them closed so that neither is closed twice.
package(flint.engine.reactor) void closeDoorbell(ref Doorbell bell) @trusted nothrow @nogc
{
    version (Posix)
    {
        if (bell.reader >= 0)
            close(bell.reader);
        if (bell.writer >= 0 && bell.writer != bell.reader)
            close(bell.writer);
    }
    bell = Doorbell.init;
}
