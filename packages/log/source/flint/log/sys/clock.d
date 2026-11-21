module flint.log.sys.clock;

import core.stdc.time : time_t, tm;
import core.sys.posix.time : CLOCK_REALTIME, clock_gettime, gmtime_r, timespec;
import flint.arena : Error, Result, Status;

@safe:

// SAFETY: clock_gettime only writes into the local typed timespec.
package(flint.log) Result!ulong timestampMillis() @trusted nothrow @nogc
{
    timespec clock;
    if (clock_gettime(CLOCK_REALTIME, &clock) != 0 || clock.tv_sec < 0
            || cast(ulong) clock.tv_sec > (ulong.max - 999) / 1000)
        return Result!ulong(0, Error(Status.ioError, "logger wall clock unavailable"));
    return Result!ulong(cast(ulong) clock.tv_sec * 1000 + cast(ulong) clock.tv_nsec / 1_000_000);
}

// SAFETY: gmtime_r borrows one local input and writes the caller's local UTC fields synchronously.
package(flint.log) bool timestampParts(ulong epochMillis, out tm utc) @trusted nothrow @nogc
{
    if (epochMillis / 1000 > time_t.max)
        return false;
    const seconds = cast(time_t)(epochMillis / 1000);
    return gmtime_r(&seconds, &utc) !is null && utc.tm_year >= -1900 && utc.tm_year <= 8099;
}
