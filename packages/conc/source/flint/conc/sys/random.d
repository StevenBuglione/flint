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
else version (OSX)
{
    import core.stdc.errno : EINTR, errno;

    // <sys/random.h>, libSystem since macOS 10.12. It reads the kernel generator and never blocks
    // once the system has booted, but returns at most 256 bytes per call.
    private extern (C) @system nothrow @nogc int getentropy(void* bytes, size_t length);

    // SAFETY: getentropy writes at most min(256, buffer.length) bytes of the mutable borrowed slice per call.
    package(flint.conc) Error secureRandom(scope ubyte[] buffer) @trusted nothrow @nogc
    {
        enum maximum = 256;
        while (buffer.length != 0)
        {
            const count = buffer.length < maximum ? buffer.length : maximum;
            if (getentropy(buffer.ptr, count) != 0)
            {
                if (errno == EINTR)
                    continue;
                return Error(Status.ioError, "operating system random source unavailable");
            }
            buffer = buffer[count .. $];
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

@("the operating system random source fills buffers longer than one kernel call")
@safe nothrow @nogc unittest
{
    ubyte[600] first, second;
    version (Posix)
    {
        assert(secureRandom(first[]).code == Status.ok);
        assert(secureRandom(second[]).code == Status.ok);
        assert(first[] != second[] && first[344 .. $] != second[344 .. $]);
    }
}
