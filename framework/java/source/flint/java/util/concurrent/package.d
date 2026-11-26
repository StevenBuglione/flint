/++
`java.util.concurrent`: `TimeUnit` (clean-room from the Java SE specification). `flint.java.util.concurrent.atomic`
holds the atomic values.
+/
module flint.java.util.concurrent;

import flint.java.time : Duration;

@safe:

/++
Java's `TimeUnit`: a duration unit with conversions between units. Conversions to a finer unit saturate at
`long.max` or `long.min` on overflow, and conversions to a coarser unit truncate toward zero, as Java's do. The
methods read as Java's through UFCS: `TimeUnit.SECONDS.toNanos(5)`, `unit.convert(d, TimeUnit.MILLISECONDS)`.
+/
enum TimeUnit
{
    /// A thousandth of a microsecond.
    NANOSECONDS,
    /// A thousandth of a millisecond.
    MICROSECONDS,
    /// A thousandth of a second.
    MILLISECONDS,
    /// One second.
    SECONDS,
    /// Sixty seconds.
    MINUTES,
    /// Sixty minutes.
    HOURS,
    /// Twenty-four hours.
    DAYS,
}

// Nanoseconds per unit, in TimeUnit order.
private immutable long[7] nanosPerUnit = [
    1L, 1_000L, 1_000_000L, 1_000_000_000L, 60_000_000_000L, 3_600_000_000_000L, 86_400_000_000_000L
];

/// `sourceDuration` of `sourceUnit` in `unit`: truncated toward zero, or saturated on overflow.
long convert(TimeUnit unit, long sourceDuration, TimeUnit sourceUnit) pure nothrow @nogc
{
    const to = nanosPerUnit[unit], from = nanosPerUnit[sourceUnit];
    if (from == to)
        return sourceDuration;
    if (from < to)
        return sourceDuration / (to / from);
    const ratio = from / to;
    const limit = long.max / ratio;
    if (sourceDuration > limit)
        return long.max;
    if (sourceDuration < -limit)
        return long.min;
    return sourceDuration * ratio;
}

/// `duration` in `unit` (Java's `TimeUnit.convert(Duration)`): truncated toward zero, saturated on overflow.
long convert(TimeUnit unit, Duration duration) pure nothrow @nogc
{
    long seconds = duration.getSeconds();
    long nanos = duration.getNano();
    // A negative duration with a nanosecond part counts toward zero: -1.5 s is -1 s and -500,000,000 ns.
    if (seconds < 0 && nanos > 0)
    {
        seconds++;
        nanos -= 1_000_000_000L;
    }
    if (unit >= TimeUnit.SECONDS)
        return convert(unit, seconds, TimeUnit.SECONDS);
    const perSecond = nanosPerUnit[TimeUnit.SECONDS] / nanosPerUnit[unit];
    const part = nanos / nanosPerUnit[unit];
    const limit = long.max / perSecond;
    if (seconds > limit || (seconds == limit && part > long.max - limit * perSecond))
        return long.max;
    if (seconds < -limit || (seconds == -limit && part < long.min + limit * perSecond))
        return long.min;
    return seconds * perSecond + part;
}

/// `duration` of `unit` in nanoseconds.
long toNanos(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.NANOSECONDS, duration, unit);
}

/// `duration` of `unit` in microseconds.
long toMicros(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.MICROSECONDS, duration, unit);
}

/// `duration` of `unit` in milliseconds.
long toMillis(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.MILLISECONDS, duration, unit);
}

/// `duration` of `unit` in seconds.
long toSeconds(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.SECONDS, duration, unit);
}

/// `duration` of `unit` in minutes.
long toMinutes(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.MINUTES, duration, unit);
}

/// `duration` of `unit` in hours.
long toHours(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.HOURS, duration, unit);
}

/// `duration` of `unit` in days.
long toDays(TimeUnit unit, long duration) pure nothrow @nogc
{
    return convert(TimeUnit.DAYS, duration, unit);
}

unittest
{
    // Exact conversions, both directions, and truncation toward zero.
    assert(TimeUnit.SECONDS.toNanos(5) == 5_000_000_000L && TimeUnit.MILLISECONDS.toMicros(3) == 3_000);
    assert(TimeUnit.NANOSECONDS.toMillis(1_999_999) == 1 && TimeUnit.NANOSECONDS.toMillis(-1_999_999) == -1);
    assert(TimeUnit.HOURS.toMinutes(2) == 120 && TimeUnit.DAYS.toHours(1) == 24 && TimeUnit.MINUTES.toDays(2_880) == 2);
    assert(TimeUnit.MICROSECONDS.convert(7, TimeUnit.MILLISECONDS) == 7_000);
    assert(TimeUnit.SECONDS.convert(90, TimeUnit.SECONDS) == 90);
}

unittest
{
    // Saturation at long.max and long.min, as Java's TimeUnit does.
    assert(TimeUnit.DAYS.toNanos(long.max) == long.max && TimeUnit.DAYS.toNanos(long.min) == long.min);
    assert(TimeUnit.SECONDS.toNanos(9_223_372_037L) == long.max && TimeUnit.SECONDS.toNanos(9_223_372_036L) > 0);
    assert(TimeUnit.NANOSECONDS.toDays(long.max) == 106_751);
}

unittest
{
    // A Duration in a unit: seconds and nanoseconds combined, saturating.
    const duration = Duration.ofNanos(2_500_000_123L);
    assert(TimeUnit.NANOSECONDS.convert(duration) == 2_500_000_123L);
    assert(TimeUnit.MILLISECONDS.convert(duration) == 2_500 && TimeUnit.SECONDS.convert(duration) == 2);
    // Negative durations truncate toward zero; huge ones saturate.
    const negative = Duration.ofNanos(-1_500_000_000L);
    assert(TimeUnit.MILLISECONDS.convert(negative) == -1_500 && TimeUnit.SECONDS.convert(negative) == -1);
    assert(TimeUnit.NANOSECONDS.convert(Duration.ofSeconds(long.max)) == long.max);
    assert(TimeUnit.NANOSECONDS.convert(Duration.ofSeconds(long.min)) == long.min);
}
