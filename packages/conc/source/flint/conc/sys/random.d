module flint.conc.sys.random;

import flint.arena : Error, Status;

@safe:

version (linux)
{
    import core.stdc.errno : EAGAIN, EINTR, errno;

    private extern (C) @system nothrow @nogc ptrdiff_t getrandom(void* bytes, size_t length, uint flags);

    // SAFETY: Linux getrandom writes at most the mutable borrowed slice and retains no address.
    package(flint.conc) Error secureRandom(scope ubyte[] buffer) @trusted nothrow @nogc
    {
        enum nonblock = 1U;
        while (buffer.length != 0)
        {
            const count = getrandom(buffer.ptr, buffer.length, nonblock);
            if (count > 0)
                buffer = buffer[cast(size_t) count .. $];
            else
            {
                const failure = errno;
                if (count < 0 && failure == EINTR)
                    continue;
                return Error(count < 0 && failure == EAGAIN ? Status.unavailable : Status.ioError,
                        "operating system random source unavailable");
            }
        }
        return Error.init;
    }
}
else
{
    package(flint.conc) Error secureRandom(scope ubyte[]) nothrow @nogc
    {
        return Error(Status.unsupported, "secure random source unavailable on this platform");
    }
}
