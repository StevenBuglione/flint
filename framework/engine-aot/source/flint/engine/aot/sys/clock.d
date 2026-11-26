/++
The wall clock behind `flint.engine.aot.clock`, as flint:log reads it (`flint.log.sys.clock`).
Private to `flint:engine-aot`; applications never import it.
+/
module flint.engine.aot.sys.clock;

@safe:

version (Windows)
{
    import core.sys.windows.winbase : FILETIME;

    private extern (Windows) void GetSystemTimePreciseAsFileTime(FILETIME* time) nothrow @nogc @system;

    /// 100 ns ticks since 1970-01-01T00:00Z, or -1 if the clock reads before the epoch.
    // SAFETY: GetSystemTimePreciseAsFileTime only writes into the local FILETIME.
    @trusted long epochTicks() nothrow @nogc
    {
        enum ulong unixEpoch = 116_444_736_000_000_000; // 1970-01-01 in 100 ns ticks since 1601-01-01.
        FILETIME clock;
        GetSystemTimePreciseAsFileTime(&clock);
        const ticks = (cast(ulong) clock.dwHighDateTime << 32) | clock.dwLowDateTime;
        return ticks < unixEpoch ? -1 : cast(long)(ticks - unixEpoch);
    }

    /// The local zone's current offset from UTC in seconds (east positive), as std.datetime's `LocalTime` reads
    /// it on Windows: the bias, with the daylight bias while daylight time is in effect; 0 when unknown.
    // SAFETY: GetTimeZoneInformation only writes into the local TIME_ZONE_INFORMATION.
    @trusted long localOffsetSeconds(long) nothrow @nogc
    {
        import core.sys.windows.winbase : GetTimeZoneInformation, TIME_ZONE_INFORMATION;

        TIME_ZONE_INFORMATION zone;
        const which = GetTimeZoneInformation(&zone);
        if (which == 0xFFFF_FFFF) // TIME_ZONE_ID_INVALID
            return 0;
        const bias = zone.Bias + (which == 2 ? zone.DaylightBias : which == 1 ? zone.StandardBias : 0);
        return -cast(long) bias * 60;
    }
}
else
{
    version (OSX)
    {
        import core.sys.posix.time : timespec;

        // macOS 10.12+ <time.h>: clockid_t is a C enum (int ABI) and CLOCK_REALTIME is 0.
        private enum int CLOCK_REALTIME = 0;
        private extern (C) int clock_gettime(int clock, timespec* value) @system nothrow @nogc;
    }
    else
        import core.sys.posix.time : CLOCK_REALTIME, clock_gettime, timespec;

    /// 100 ns ticks since 1970-01-01T00:00Z, or -1 if the clock is unavailable or reads before the epoch.
    // SAFETY: clock_gettime only writes into the local typed timespec.
    @trusted long epochTicks() nothrow @nogc
    {
        timespec clock;
        if (clock_gettime(CLOCK_REALTIME, &clock) != 0 || clock.tv_sec < 0)
            return -1;
        return cast(long) clock.tv_sec * 10_000_000 + cast(long) clock.tv_nsec / 100;
    }

    /// The local zone's offset from UTC in seconds (east positive) at `epochSeconds`, as std.datetime's
    /// `LocalTime` reads it: localtime_r's tm_gmtoff after tzset, so a changed `TZ` takes effect; 0 when the
    /// conversion fails.
    // SAFETY: tzset takes no arguments; localtime_r reads the local time_t and writes only the local tm; tm_zone
    // is never read.
    @trusted long localOffsetSeconds(long epochSeconds) nothrow @nogc
    {
        import core.sys.posix.stdc.time : tm, tzset;
        import core.sys.posix.sys.types : time_t;
        import core.sys.posix.time : localtime_r;

        tzset();
        const time_t at = cast(time_t) epochSeconds;
        tm local;
        if (localtime_r(&at, &local) is null)
            return 0;
        return cast(long) local.tm_gmtoff;
    }
}

unittest
{
    import std.datetime.systime : Clock;

    // Positive: agrees with std.datetime's clock to within the time between the two reads.
    enum long unixEpochInHnsecs = 621_355_968_000_000_000;
    const before = Clock.currStdTime - unixEpochInHnsecs;
    const now = epochTicks();
    const after = Clock.currStdTime - unixEpochInHnsecs;
    assert(before <= now && now <= after);
    // Negative: never the failure value on a working clock, and never decreasing between two reads.
    assert(now != -1 && epochTicks() >= now);
}

version (Posix) unittest
{
    import std.datetime.systime : Clock, SysTime;
    import std.datetime.timezone : LocalTime;

    // Positive: std.datetime's local offset now and half a year ago (either side of a daylight change).
    const now = Clock.currTime(LocalTime());
    foreach (seconds; [now.toUnixTime!long, now.toUnixTime!long - 182 * 86_400])
        assert(localOffsetSeconds(seconds) == SysTime.fromUnixTime(seconds, LocalTime()).utcOffset.total!"seconds");
    // Negative: an offset is within a day either way, also for the epoch and far dates.
    foreach (seconds; [0L, -1L, 4_102_444_800L])
        assert(localOffsetSeconds(seconds) > -86_400 && localOffsetSeconds(seconds) < 86_400);
    // TZ, as localtime reads it, takes effect on the next call.
    import std.process : environment;

    const saved = environment.get("TZ", null);
    scope (exit)
    {
        if (saved is null)
            environment.remove("TZ");
        else
            environment["TZ"] = saved;
        cast(void) localOffsetSeconds(0);
    }
    environment["TZ"] = "UTC0";
    assert(localOffsetSeconds(1_767_225_600) == 0);
    environment["TZ"] = "EST5";
    assert(localOffsetSeconds(1_767_225_600) == -5 * 3600);
    environment["TZ"] = "IST-5:30";
    assert(localOffsetSeconds(1_767_225_600) == 5 * 3600 + 1800);
}
