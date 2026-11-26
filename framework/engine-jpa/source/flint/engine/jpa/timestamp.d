/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Scalar conversions for the opt-in JDBC TIMESTAMP codec.
module flint.engine.jpa.timestamp;

import flint.arena : Error, Result, Status;

@safe:

private enum nanosPerMicro = 1_000L;
private enum microsPerDay = 86_400_000_000L;
private enum nanosPerDay = microsPerDay * nanosPerMicro;
private enum firstEpochDay = -719_162L; // 0001-01-01
private enum lastEpochDay = 2_932_896L; // 9999-12-31
private enum firstTimestamp = firstEpochDay * microsPerDay;
private enum endTimestamp = (lastEpochDay + 1) * microsPerDay;
private enum rangeError = Error(Status.invalidArgument, "TIMESTAMP is outside the supported range");

/// Local date and time fields relative to midnight, independent of the application time type.
struct TimestampParts
{
    /// Days since 1970-01-01, possibly negative.
    long epochDay;
    /// Nanoseconds elapsed since the start of that day.
    long nanoOfDay;
}

/// Packs an ISO date in years 0001–9999 as signed epoch microseconds. Ties round toward the next instant, as pgjdbc
/// 42.7.14 does for LocalDateTime. A carry beyond 9999-12-31 is out of range.
Result!long encodeTimestampMicros(long epochDay, long nanoOfDay) pure nothrow @nogc
{
    if (epochDay < firstEpochDay || epochDay > lastEpochDay || nanoOfDay < 0 || nanoOfDay >= nanosPerDay)
        return Result!long(0, rangeError);
    const micros = epochDay * microsPerDay + (nanoOfDay + nanosPerMicro / 2) / nanosPerMicro;
    if (micros >= endTimestamp)
        return Result!long(0, rangeError);
    return Result!long(micros);
}

/// Unpacks an epoch-microsecond value in years 0001–9999. The time of day is always nonnegative.
Result!TimestampParts decodeTimestampMicros(long micros) pure nothrow @nogc
{
    if (micros < firstTimestamp || micros >= endTimestamp)
        return Result!TimestampParts(TimestampParts.init, rangeError);
    auto epochDay = micros / microsPerDay;
    auto withinDay = micros % microsPerDay;
    if (withinDay < 0)
    {
        --epochDay;
        withinDay += microsPerDay;
    }
    return Result!TimestampParts(TimestampParts(epochDay, withinDay * nanosPerMicro));
}
