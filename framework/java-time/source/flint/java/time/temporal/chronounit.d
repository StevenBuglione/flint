/// Built-in Java SE 21 temporal unit metadata (R18).
module flint.java.time.temporal.chronounit;

import flint.java.time : Duration;

@safe:

/// Standard temporal units in Java declaration order.
enum ChronoUnit : ubyte
{
    NANOS,
    MICROS,
    MILLIS,
    SECONDS,
    MINUTES,
    HOURS,
    HALF_DAYS,
    DAYS,
    WEEKS,
    MONTHS,
    YEARS,
    DECADES,
    CENTURIES,
    MILLENNIA,
    ERAS,
    FOREVER,
}

private enum unitCount = cast(size_t) ChronoUnit.max + 1;

private immutable Duration[unitCount] durations = [
    ChronoUnit.NANOS: Duration.ofSeconds(0, 1), ChronoUnit.MICROS: Duration.ofSeconds(0, 1_000),
    ChronoUnit.MILLIS: Duration.ofSeconds(0, 1_000_000), ChronoUnit.SECONDS: Duration.ofSeconds(1),
    ChronoUnit.MINUTES: Duration.ofSeconds(60), ChronoUnit.HOURS: Duration.ofSeconds(3_600),
    ChronoUnit.HALF_DAYS: Duration.ofSeconds(43_200), ChronoUnit.DAYS: Duration.ofSeconds(86_400),
    ChronoUnit.WEEKS: Duration.ofSeconds(604_800), ChronoUnit.MONTHS: Duration.ofSeconds(2_629_746),
    ChronoUnit.YEARS: Duration.ofSeconds(31_556_952),
    ChronoUnit.DECADES: Duration.ofSeconds(315_569_520),
    ChronoUnit.CENTURIES: Duration.ofSeconds(3_155_695_200),
    ChronoUnit.MILLENNIA: Duration.ofSeconds(31_556_952_000),
    ChronoUnit.ERAS: Duration.ofSeconds(31_556_952_000_000_000),
    ChronoUnit.FOREVER: Duration.ofSeconds(long.max, 999_999_999),
];

private immutable string[unitCount] displayNames = [
    ChronoUnit.NANOS: "Nanos", ChronoUnit.MICROS: "Micros", ChronoUnit.MILLIS: "Millis",
    ChronoUnit.SECONDS: "Seconds", ChronoUnit.MINUTES: "Minutes", ChronoUnit.HOURS: "Hours",
    ChronoUnit.HALF_DAYS: "HalfDays", ChronoUnit.DAYS: "Days", ChronoUnit.WEEKS: "Weeks",
    ChronoUnit.MONTHS: "Months", ChronoUnit.YEARS: "Years", ChronoUnit.DECADES: "Decades",
    ChronoUnit.CENTURIES: "Centuries", ChronoUnit.MILLENNIA: "Millennia", ChronoUnit.ERAS: "Eras",
    ChronoUnit.FOREVER: "Forever",
];

/// The unit's ISO duration, which can be an estimate for calendar units.
Duration getDuration(ChronoUnit unit) pure nothrow @nogc
{
    return durations[unit];
}

bool isDurationEstimated(ChronoUnit unit) pure nothrow @nogc
{
    return unit >= ChronoUnit.DAYS;
}

bool isDateBased(ChronoUnit unit) pure nothrow @nogc
{
    return unit >= ChronoUnit.DAYS && unit <= ChronoUnit.ERAS;
}

bool isTimeBased(ChronoUnit unit) pure nothrow @nogc
{
    return unit <= ChronoUnit.HALF_DAYS;
}

/// The unit's plain display name.
string toString(ChronoUnit unit) pure nothrow @nogc
{
    return displayNames[unit];
}
