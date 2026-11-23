// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/convert/DurationUnit.java
// with DurationStyle.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `ChronoUnit` is declared here until `flint.java.time.temporal` exists.

/// `org.springframework.boot.convert`: Boot's conversion annotations.
///
/// Annotation module: a leaf of UDA structs and one enum. `@DurationUnit(ChronoUnit.SECONDS)` on a property makes a
/// bare number in its value (`30`) mean seconds instead of milliseconds, as in Boot.
module flint.boot.convert;

@safe:

/// `java.time.temporal.ChronoUnit`'s time-based units; a stand-in until `flint.java.time.temporal.ChronoUnit`.
enum ChronoUnit
{
    /// Nanoseconds.
    NANOS,
    /// Microseconds.
    MICROS,
    /// Milliseconds.
    MILLIS,
    /// Seconds.
    SECONDS,
    /// Minutes.
    MINUTES,
    /// Hours.
    HOURS,
    /// Days.
    DAYS
}

/// The unit of a `Duration` property's bare numbers.
struct DurationUnit
{
    /// The unit.
    ChronoUnit value = ChronoUnit.MILLIS;
}
