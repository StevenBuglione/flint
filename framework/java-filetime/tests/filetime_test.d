// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.nio.file.attribute.filetime_test;

import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.time : Instant;
import flint.java.util.concurrent : TimeUnit, convert;

@safe:

private enum long minSecond = -31_557_014_167_219_200L;
private enum long maxSecond = 31_556_889_864_403_199L;

@("from a value and unit equals the same point in another unit")
unittest
{
    const now = 1_700_000_000_123L;
    FileTime millis = FileTime.from(now, TimeUnit.MILLISECONDS);
    FileTime micros = FileTime.from(now * 1000L, TimeUnit.MICROSECONDS);
    assert(millis.equals(micros));
    assert(millis == micros);
    assert(millis.hashCode() == micros.hashCode());
    assert(!millis.equals(FileTime.from(0, TimeUnit.MILLISECONDS)));
    assert(!FileTime.from(Instant.ofEpochMilli(now)).equals(FileTime.from(0, TimeUnit.MILLISECONDS)));
    assert(FileTime.from(Instant.ofEpochMilli(now)).equals(millis));
}

@("compareTo orders values and units")
unittest
{
    const now = 1_700_000_000_123L;
    FileTime millis = FileTime.from(now, TimeUnit.MILLISECONDS);
    assert(millis.compareTo(FileTime.from(now, TimeUnit.MILLISECONDS)) == 0);
    assert(millis.compareTo(FileTime.from(now * 1000L, TimeUnit.MICROSECONDS)) == 0);
    assert(millis.compareTo(FileTime.from(now - 1234, TimeUnit.MILLISECONDS)) > 0);
    assert(millis.compareTo(FileTime.from(now + 1234, TimeUnit.MILLISECONDS)) < 0);
    const tomorrowDays = TimeUnit.DAYS.convert(now, TimeUnit.MILLISECONDS) + 1;
    const yesterdayDays = TimeUnit.DAYS.convert(now, TimeUnit.MILLISECONDS) - 1;
    assert(FileTime.from(tomorrowDays, TimeUnit.DAYS).compareTo(millis) > 0);
    assert(millis.compareTo(FileTime.from(tomorrowDays, TimeUnit.DAYS)) < 0);
    assert(FileTime.from(yesterdayDays, TimeUnit.DAYS).compareTo(millis) < 0);
    assert(millis.compareTo(FileTime.from(yesterdayDays, TimeUnit.DAYS)) > 0);
}

@("compareTo handles the ends of the range")
unittest
{
    const instantMin = Instant.ofEpochSecond(minSecond, 0);
    const instantMax = Instant.ofEpochSecond(maxSecond, 999_999_999);
    assert(FileTime.from(long.max, TimeUnit.DAYS).compareTo(FileTime.from(long.max, TimeUnit.NANOSECONDS)) > 0);
    assert(FileTime.from(long.min, TimeUnit.DAYS).compareTo(FileTime.from(long.min, TimeUnit.NANOSECONDS)) < 0);
    assert(FileTime.from(instantMin).compareTo(FileTime.from(long.min, TimeUnit.DAYS)) > 0);
    assert(FileTime.from(instantMin).compareTo(FileTime.from(minSecond, TimeUnit.SECONDS)) == 0);
    assert(FileTime.from(instantMin).compareTo(FileTime.from(minSecond - 1, TimeUnit.SECONDS)) > 0);
    assert(FileTime.from(instantMax).compareTo(FileTime.from(long.max, TimeUnit.DAYS)) < 0);
    assert(FileTime.from(instantMax).compareTo(FileTime.from(maxSecond, TimeUnit.SECONDS)) == 0);
    assert(FileTime.from(instantMax).compareTo(FileTime.from(maxSecond + 1, TimeUnit.SECONDS)) < 0);
}

@("to converts between every unit like TimeUnit")
unittest
{
    foreach (unit; [
        TimeUnit.NANOSECONDS, TimeUnit.MICROSECONDS, TimeUnit.MILLISECONDS, TimeUnit.SECONDS,
        TimeUnit.MINUTES, TimeUnit.HOURS, TimeUnit.DAYS
    ])
    {
        foreach (value; [-1_700_000_000_123L, 0L, 1L, 86_400_000L, 1_700_000_000_123L])
        {
            FileTime time = FileTime.from(value, unit);
            foreach (target; [
                TimeUnit.NANOSECONDS, TimeUnit.MICROSECONDS, TimeUnit.MILLISECONDS,
                TimeUnit.SECONDS, TimeUnit.MINUTES, TimeUnit.HOURS, TimeUnit.DAYS
            ])
                assert(time.to(target) == target.convert(value, unit));
        }
    }
}

@("toInstant round-trips and saturates")
unittest
{
    foreach (unit; [
        TimeUnit.NANOSECONDS, TimeUnit.MICROSECONDS, TimeUnit.MILLISECONDS, TimeUnit.SECONDS,
        TimeUnit.MINUTES, TimeUnit.HOURS, TimeUnit.DAYS
    ])
    {
        foreach (value; [-1_700_000_000_123L, 0L, 1L, 1_999_999L, 1_700_000_000_123L])
        {
            const instant = FileTime.from(value, unit).toInstant();
            const secs = TimeUnit.SECONDS.convert(value, unit);
            auto nanos = TimeUnit.NANOSECONDS.convert(value - unit.convert(secs, TimeUnit.SECONDS), unit);
            long normalized = secs;
            if (nanos < 0)
            {
                normalized -= 1;
                nanos += 1_000_000_000L;
            }
            if (normalized > minSecond && normalized < maxSecond)
            {
                assert(instant.getEpochSecond() == normalized);
                assert(instant.getNano() == cast(int) nanos);
            }
        }
        assert(FileTime.from(Instant.ofEpochSecond(minSecond, 0)).toInstant() == Instant.ofEpochSecond(minSecond, 0));
        if (unit >= TimeUnit.SECONDS)
            assert(FileTime.from(long.min, unit).toInstant() == Instant.ofEpochSecond(minSecond, 0));
        if (unit >= TimeUnit.SECONDS)
            assert(FileTime.from(long.max, unit).toInstant() == Instant.ofEpochSecond(maxSecond, 999_999_999));
    }
}

@("from an instant keeps seconds and millis")
unittest
{
    const instant = Instant.ofEpochSecond(1_234_567_890L, 987_654_321);
    FileTime time = FileTime.from(instant);
    assert(time.toInstant() == instant);
    assert(time.to(TimeUnit.SECONDS) == 1_234_567_890L);
    assert(time.toMillis() == 1_234_567_890_987L);
    assert(FileTime.from(Instant.ofEpochMilli(1_700_000_000_123L)).toMillis() == 1_700_000_000_123L);
    assert(FileTime.from(1_999_999_999L, TimeUnit.NANOSECONDS)
            .equals(FileTime.from(Instant.ofEpochSecond(1, 999_999_999))));
}

@("toString prints the ISO-8601 form")
unittest
{
    assert(FileTime.from(1, TimeUnit.DAYS).toString == "1970-01-02T00:00:00Z");
    assert(FileTime.from(1, TimeUnit.HOURS).toString == "1970-01-01T01:00:00Z");
    assert(FileTime.from(1, TimeUnit.MINUTES).toString == "1970-01-01T00:01:00Z");
    assert(FileTime.from(1, TimeUnit.SECONDS).toString == "1970-01-01T00:00:01Z");
    assert(FileTime.from(1, TimeUnit.MILLISECONDS).toString == "1970-01-01T00:00:00.001Z");
    assert(FileTime.from(1, TimeUnit.MICROSECONDS).toString == "1970-01-01T00:00:00.000001Z");
    assert(FileTime.from(1, TimeUnit.NANOSECONDS).toString == "1970-01-01T00:00:00.000000001Z");
    assert(FileTime.from(999_999_999L, TimeUnit.NANOSECONDS).toString == "1970-01-01T00:00:00.999999999Z");
    assert(FileTime.from(9_999_999_999L, TimeUnit.NANOSECONDS).toString == "1970-01-01T00:00:09.999999999Z");
    assert(FileTime.from(-1, TimeUnit.DAYS).toString == "1969-12-31T00:00:00Z");
    assert(FileTime.from(-1, TimeUnit.HOURS).toString == "1969-12-31T23:00:00Z");
    assert(FileTime.from(-1, TimeUnit.MINUTES).toString == "1969-12-31T23:59:00Z");
    assert(FileTime.from(-1, TimeUnit.SECONDS).toString == "1969-12-31T23:59:59Z");
    assert(FileTime.from(-1, TimeUnit.MILLISECONDS).toString == "1969-12-31T23:59:59.999Z");
    assert(FileTime.from(-1, TimeUnit.MICROSECONDS).toString == "1969-12-31T23:59:59.999999Z");
    assert(FileTime.from(-1, TimeUnit.NANOSECONDS).toString == "1969-12-31T23:59:59.999999999Z");
    assert(FileTime.from(-999_999_999L, TimeUnit.NANOSECONDS).toString == "1969-12-31T23:59:59.000000001Z");
    assert(FileTime.from(-9_999_999_999L, TimeUnit.NANOSECONDS).toString == "1969-12-31T23:59:50.000000001Z");
    assert(FileTime.from(-62_135_596_799_999L, TimeUnit.MILLISECONDS).toString == "0001-01-01T00:00:00.001Z");
    assert(FileTime.from(-62_135_596_800_000L, TimeUnit.MILLISECONDS).toString == "0001-01-01T00:00:00Z");
    assert(FileTime.from(-62_135_596_800_001L, TimeUnit.MILLISECONDS).toString == "-0001-12-31T23:59:59.999Z");
    assert(FileTime.from(253_402_300_799_999L, TimeUnit.MILLISECONDS).toString == "9999-12-31T23:59:59.999Z");
    assert(FileTime.from(-377_642_044_800_001L, TimeUnit.MILLISECONDS).toString == "-9999-12-31T23:59:59.999Z");
    assert(FileTime.from(-11_644_473_600_000_000L, TimeUnit.MICROSECONDS).toString == "1601-01-01T00:00:00Z");
    assert(FileTime.from(Instant.ofEpochSecond(minSecond, 0)).toString == "-1000000001-01-01T00:00:00Z");
    assert(FileTime.from(Instant.ofEpochSecond(maxSecond, 999_999_999))
            .toString == "1000000000-12-31T23:59:59.999999999Z");
}

@("toMillis saturates beyond the long range")
unittest
{
    assert(FileTime.from(Instant.ofEpochSecond(maxSecond, 999_999_999)).toMillis() == long.max);
    assert(FileTime.from(Instant.ofEpochSecond(long.max / 1000 + 1)).toMillis() == long.max);
    assert(FileTime.from(Instant.ofEpochSecond(minSecond, 0)).toMillis() == long.min);
    assert(FileTime.from(Instant.ofEpochSecond(long.min / 1000 - 1)).toMillis() == long.min);
}
