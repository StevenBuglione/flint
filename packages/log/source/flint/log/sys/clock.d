module flint.log.sys.clock;

import flint.arena : Error, Result, Status;

@safe:

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

@("RFC 3339 text matches the C library UTC conversion from 1970 through 9999")
@system unittest
{
    import core.stdc.stdio : snprintf;
    import core.stdc.time : time_t, tm;
    import core.sys.posix.time : gmtime_r;
    import flint.log.encoding : utcText;

    void check(ulong millis)
    {
        char[24] text;
        tm utc;
        const seconds = cast(time_t)(millis / 1000);
        assert(gmtime_r(&seconds, &utc) !is null);
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
