module flint.log.sys.clock;

import flint.arena : Error, Result, Status;

@safe:

version (Windows)
{
    import core.sys.windows.winbase : FILETIME;

    private extern (Windows) void GetSystemTimePreciseAsFileTime(FILETIME* time) nothrow @nogc @system;

    // SAFETY: GetSystemTimePreciseAsFileTime only writes into the local FILETIME.
    package(flint.log) Result!ulong timestampMillis() @trusted nothrow @nogc
    {
        enum ulong unixEpoch = 116_444_736_000_000_000; // 1970-01-01 in 100 ns ticks since 1601-01-01.
        FILETIME clock;
        GetSystemTimePreciseAsFileTime(&clock);
        const ticks = (cast(ulong) clock.dwHighDateTime << 32) | clock.dwLowDateTime;
        if (ticks < unixEpoch)
            return Result!ulong(0, Error(Status.ioError, "logger wall clock unavailable"));
        return Result!ulong((ticks - unixEpoch) / 10_000);
    }
}
else
{
    version (OSX)
    {
        import core.sys.posix.time : timespec;

        // macOS 10.12+ <time.h>: clockid_t is a C enum (int ABI) and CLOCK_REALTIME is 0.
        // druntime declares neither for Darwin.
        private enum int CLOCK_REALTIME = 0;
        private extern (C) int clock_gettime(int clock, timespec* value) @system nothrow @nogc;
    }
    else
        import core.sys.posix.time : CLOCK_REALTIME, clock_gettime, timespec;

    // SAFETY: clock_gettime only writes into the local typed timespec.
    package(flint.log) Result!ulong timestampMillis() @trusted nothrow @nogc
    {
        timespec clock;
        if (clock_gettime(CLOCK_REALTIME, &clock) != 0 || clock.tv_sec < 0
                || cast(ulong) clock.tv_sec > (ulong.max - 999) / 1000)
            return Result!ulong(0, Error(Status.ioError, "logger wall clock unavailable"));
        return Result!ulong(cast(ulong) clock.tv_sec * 1000 + cast(ulong) clock.tv_nsec / 1_000_000);
    }
}

@("RFC 3339 text matches the C library UTC conversion from 1970 through 9999")
@system unittest
{
    import core.stdc.stdio : snprintf;
    import core.stdc.time : time_t, tm;
    import flint.log.encoding : utcText;

    version (Windows)
    {
        // The C runtime's gmtime stops at year 3000; FileTimeToSystemTime covers the whole range.
        // time_t is 32 bits in the Microsoft C runtime, so the reference takes the 64-bit second count.
        bool gmtime_r(const ulong* seconds, tm* utc)
        {
            import core.sys.windows.winbase : FILETIME, FileTimeToSystemTime, SYSTEMTIME;

            const ticks = *seconds * 10_000_000 + 116_444_736_000_000_000;
            FILETIME file = FILETIME(cast(uint) ticks, cast(uint)(ticks >> 32));
            SYSTEMTIME system;
            if (!FileTimeToSystemTime(&file, &system))
                return false;
            *utc = tm.init;
            utc.tm_sec = system.wSecond;
            utc.tm_min = system.wMinute;
            utc.tm_hour = system.wHour;
            utc.tm_mday = system.wDay;
            utc.tm_mon = system.wMonth - 1;
            utc.tm_year = system.wYear - 1900;
            return true;
        }
    }
    else
        import core.sys.posix.time : gmtime_r;

    void check(ulong millis)
    {
        char[24] text;
        tm utc;
        version (Windows)
            const seconds = millis / 1000;
        else
            const seconds = cast(time_t)(millis / 1000);
        assert(gmtime_r(&seconds, &utc));
        assert(utcText(millis, text) == (utc.tm_year + 1900 <= 9999));
        if (utc.tm_year + 1900 > 9999)
            return;
        char[64] expected;
        const length = snprintf(expected.ptr, expected.length, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday, utc.tm_hour, utc.tm_min,
                utc.tm_sec, cast(int)(millis % 1000));
        assert(length == 24 && text[] == expected[0 .. 24]);
    }

    enum ulong day = 86_400_000;
    foreach (ulong days; 0 .. 4 * 146_097 + 3)
        check(days * day + (days * 7_919_993) % day);
    foreach (ulong second; 0 .. 100_000)
        check(second * 997 + second % 1000);
    foreach (ulong millis; [
        951_782_400_000UL, 4_107_542_399_999UL, 253_402_300_799_999UL, 253_402_300_800_000UL,
        253_402_300_800_000UL + 365 * day
    ])
        check(millis);
}
