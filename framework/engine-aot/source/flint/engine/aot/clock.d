/++
Java's `System.currentTimeMillis()` without `std.datetime`, whose `Clock` instantiates its templates in every module
that asks for the time (ADR-030 section 5).
+/
module flint.engine.aot.clock;

import flint.engine.aot.sys.clock : epochMillis, epochTicks, localOffsetSeconds;

@safe:

/// Signed milliseconds since 1970-01-01T00:00Z, as `System.currentTimeMillis()`; 0 if the wall clock is unavailable.
long currentTimeMillis() nothrow @nogc
{
    return epochMillis();
}

/++
100 ns ticks since 1970-01-01T00:00Z, the resolution of std.datetime's `Clock.currStdTime` (which counts from
0001-01-01); 0 if the wall clock is unavailable or before the epoch. `Instant.now()` splits it into seconds and nanoseconds.
+/
long currentTimeTicks() nothrow @nogc
{
    const ticks = epochTicks();
    return ticks < 0 ? 0 : ticks;
}

/++
The local zone's current offset from UTC in minutes (east positive), as std.datetime's
`Clock.currTime.utcOffset.total!"minutes"`; 0 when it cannot be read. On POSIX it follows `TZ` as localtime does
(tzset first). On Windows it is the system zone's current bias (GetTimeZoneInformation): `TZ` is not read, and the
offset is today's, so an instant on the other side of a daylight-saving change would get today's offset. That suits
log timestamps, its use; code that converts past or future instants needs a zone database. The lookup uses the clamped
tick clock.
+/
int localOffsetMinutes() nothrow @nogc
{
    return cast(int)(localOffsetSeconds(currentTimeTicks() / 10_000_000) / 60);
}

unittest
{
    import std.datetime.systime : Clock;

    assert(localOffsetMinutes() == Clock.currTime.utcOffset.total!"minutes");
}

unittest
{
    // 2026-01-01T00:00Z: any working clock reads later.
    assert(currentTimeMillis() > 1_767_225_600_000);
    assert(currentTimeTicks() > 17_672_256_000_000_000);
}
