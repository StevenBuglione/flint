/// Built-in Java SE 21 temporal field metadata (R18).
module flint.java.time.temporal.chronofield;

import flint.java.time.temporal.chronounit : ChronoUnit;
import flint.java.time.temporal.valuerange : ValueRange;

@safe:

/// Standard temporal fields in Java declaration order.
enum ChronoField : ubyte
{
    NANO_OF_SECOND,
    NANO_OF_DAY,
    MICRO_OF_SECOND,
    MICRO_OF_DAY,
    MILLI_OF_SECOND,
    MILLI_OF_DAY,
    SECOND_OF_MINUTE,
    SECOND_OF_DAY,
    MINUTE_OF_HOUR,
    MINUTE_OF_DAY,
    HOUR_OF_AMPM,
    CLOCK_HOUR_OF_AMPM,
    HOUR_OF_DAY,
    CLOCK_HOUR_OF_DAY,
    AMPM_OF_DAY,
    DAY_OF_WEEK,
    ALIGNED_DAY_OF_WEEK_IN_MONTH,
    ALIGNED_DAY_OF_WEEK_IN_YEAR,
    DAY_OF_MONTH,
    DAY_OF_YEAR,
    EPOCH_DAY,
    ALIGNED_WEEK_OF_MONTH,
    ALIGNED_WEEK_OF_YEAR,
    MONTH_OF_YEAR,
    PROLEPTIC_MONTH,
    YEAR_OF_ERA,
    YEAR,
    ERA,
    INSTANT_SECONDS,
    OFFSET_SECONDS,
}

private enum fieldCount = cast(size_t) ChronoField.max + 1;

// Evaluate the factories at compile time, keeping the full long bounds.
private immutable ValueRange[fieldCount] ranges = [
    ChronoField.NANO_OF_SECOND: ValueRange.of(0, 999_999_999),
    ChronoField.NANO_OF_DAY: ValueRange.of(0, 86_399_999_999_999),
    ChronoField.MICRO_OF_SECOND: ValueRange.of(0, 999_999),
    ChronoField.MICRO_OF_DAY: ValueRange.of(0, 86_399_999_999),
    ChronoField.MILLI_OF_SECOND: ValueRange.of(0, 999),
    ChronoField.MILLI_OF_DAY: ValueRange.of(0, 86_399_999),
    ChronoField.SECOND_OF_MINUTE: ValueRange.of(0, 59),
    ChronoField.SECOND_OF_DAY: ValueRange.of(0, 86_399),
    ChronoField.MINUTE_OF_HOUR: ValueRange.of(0, 59),
    ChronoField.MINUTE_OF_DAY: ValueRange.of(0, 1_439), ChronoField.HOUR_OF_AMPM: ValueRange.of(0, 11),
    ChronoField.CLOCK_HOUR_OF_AMPM: ValueRange.of(1, 12),
    ChronoField.HOUR_OF_DAY: ValueRange.of(0, 23), ChronoField.CLOCK_HOUR_OF_DAY: ValueRange.of(1,
            24), ChronoField.AMPM_OF_DAY: ValueRange.of(0, 1),
    ChronoField.DAY_OF_WEEK: ValueRange.of(1, 7),
    ChronoField.ALIGNED_DAY_OF_WEEK_IN_MONTH: ValueRange.of(1, 7),
    ChronoField.ALIGNED_DAY_OF_WEEK_IN_YEAR: ValueRange.of(1, 7),
    ChronoField.DAY_OF_MONTH: ValueRange.of(1, 28, 31),
    ChronoField.DAY_OF_YEAR: ValueRange.of(1, 365, 366),
    ChronoField.EPOCH_DAY: ValueRange.of(-365_243_219_162, 365_241_780_471),
    ChronoField.ALIGNED_WEEK_OF_MONTH: ValueRange.of(1, 4, 5),
    ChronoField.ALIGNED_WEEK_OF_YEAR: ValueRange.of(1, 53),
    ChronoField.MONTH_OF_YEAR: ValueRange.of(1, 12),
    ChronoField.PROLEPTIC_MONTH: ValueRange.of(-11_999_999_988, 11_999_999_999),
    ChronoField.YEAR_OF_ERA: ValueRange.of(1, 999_999_999, 1_000_000_000),
    ChronoField.YEAR: ValueRange.of(-999_999_999, 999_999_999), ChronoField.ERA: ValueRange.of(0, 1),
    ChronoField.INSTANT_SECONDS: ValueRange.of(long.min, long.max),
    ChronoField.OFFSET_SECONDS: ValueRange.of(-64_800, 64_800),
];

private immutable string[fieldCount] displayNames = [
    ChronoField.NANO_OF_SECOND: "NanoOfSecond", ChronoField.NANO_OF_DAY: "NanoOfDay",
    ChronoField.MICRO_OF_SECOND: "MicroOfSecond", ChronoField.MICRO_OF_DAY: "MicroOfDay",
    ChronoField.MILLI_OF_SECOND: "MilliOfSecond", ChronoField.MILLI_OF_DAY: "MilliOfDay",
    ChronoField.SECOND_OF_MINUTE: "SecondOfMinute", ChronoField.SECOND_OF_DAY: "SecondOfDay",
    ChronoField.MINUTE_OF_HOUR: "MinuteOfHour", ChronoField.MINUTE_OF_DAY: "MinuteOfDay",
    ChronoField.HOUR_OF_AMPM: "HourOfAmPm", ChronoField.CLOCK_HOUR_OF_AMPM: "ClockHourOfAmPm",
    ChronoField.HOUR_OF_DAY: "HourOfDay", ChronoField.CLOCK_HOUR_OF_DAY: "ClockHourOfDay",
    ChronoField.AMPM_OF_DAY: "AmPmOfDay", ChronoField.DAY_OF_WEEK: "DayOfWeek",
    ChronoField.ALIGNED_DAY_OF_WEEK_IN_MONTH: "AlignedDayOfWeekInMonth",
    ChronoField.ALIGNED_DAY_OF_WEEK_IN_YEAR: "AlignedDayOfWeekInYear",
    ChronoField.DAY_OF_MONTH: "DayOfMonth", ChronoField.DAY_OF_YEAR: "DayOfYear",
    ChronoField.EPOCH_DAY: "EpochDay", ChronoField.ALIGNED_WEEK_OF_MONTH: "AlignedWeekOfMonth",
    ChronoField.ALIGNED_WEEK_OF_YEAR: "AlignedWeekOfYear", ChronoField.MONTH_OF_YEAR: "MonthOfYear",
    ChronoField.PROLEPTIC_MONTH: "ProlepticMonth", ChronoField.YEAR_OF_ERA: "YearOfEra",
    ChronoField.YEAR: "Year", ChronoField.ERA: "Era", ChronoField.INSTANT_SECONDS: "InstantSeconds",
    ChronoField.OFFSET_SECONDS: "OffsetSeconds",
];

/// The general bounds for the field, independent of any date or time value.
ValueRange range(ChronoField field) pure nothrow @nogc
{
    return ranges[field];
}

bool isDateBased(ChronoField field) pure nothrow @nogc
{
    return field >= ChronoField.DAY_OF_WEEK && field <= ChronoField.ERA;
}

bool isTimeBased(ChronoField field) pure nothrow @nogc
{
    return field <= ChronoField.AMPM_OF_DAY;
}

/// The field's canonical, non-localized display name.
string toString(ChronoField field) pure nothrow @nogc
{
    return displayNames[field];
}

private struct FieldUnits
{
    ChronoUnit base;
    ChronoUnit span;
}

private immutable FieldUnits[fieldCount] units = [
    ChronoField.NANO_OF_SECOND: FieldUnits(ChronoUnit.NANOS, ChronoUnit.SECONDS),
    ChronoField.NANO_OF_DAY: FieldUnits(ChronoUnit.NANOS, ChronoUnit.DAYS),
    ChronoField.MICRO_OF_SECOND: FieldUnits(ChronoUnit.MICROS, ChronoUnit.SECONDS),
    ChronoField.MICRO_OF_DAY: FieldUnits(ChronoUnit.MICROS, ChronoUnit.DAYS),
    ChronoField.MILLI_OF_SECOND: FieldUnits(ChronoUnit.MILLIS, ChronoUnit.SECONDS),
    ChronoField.MILLI_OF_DAY: FieldUnits(ChronoUnit.MILLIS, ChronoUnit.DAYS),
    ChronoField.SECOND_OF_MINUTE: FieldUnits(ChronoUnit.SECONDS, ChronoUnit.MINUTES),
    ChronoField.SECOND_OF_DAY: FieldUnits(ChronoUnit.SECONDS, ChronoUnit.DAYS),
    ChronoField.MINUTE_OF_HOUR: FieldUnits(ChronoUnit.MINUTES, ChronoUnit.HOURS),
    ChronoField.MINUTE_OF_DAY: FieldUnits(ChronoUnit.MINUTES, ChronoUnit.DAYS),
    ChronoField.HOUR_OF_AMPM: FieldUnits(ChronoUnit.HOURS, ChronoUnit.HALF_DAYS),
    ChronoField.CLOCK_HOUR_OF_AMPM: FieldUnits(ChronoUnit.HOURS, ChronoUnit.HALF_DAYS),
    ChronoField.HOUR_OF_DAY: FieldUnits(ChronoUnit.HOURS, ChronoUnit.DAYS),
    ChronoField.CLOCK_HOUR_OF_DAY: FieldUnits(ChronoUnit.HOURS, ChronoUnit.DAYS),
    ChronoField.AMPM_OF_DAY: FieldUnits(ChronoUnit.HALF_DAYS, ChronoUnit.DAYS),
    ChronoField.DAY_OF_WEEK: FieldUnits(ChronoUnit.DAYS, ChronoUnit.WEEKS),
    ChronoField.ALIGNED_DAY_OF_WEEK_IN_MONTH: FieldUnits(ChronoUnit.DAYS, ChronoUnit.WEEKS),
    ChronoField.ALIGNED_DAY_OF_WEEK_IN_YEAR: FieldUnits(ChronoUnit.DAYS, ChronoUnit.WEEKS),
    ChronoField.DAY_OF_MONTH: FieldUnits(ChronoUnit.DAYS, ChronoUnit.MONTHS),
    ChronoField.DAY_OF_YEAR: FieldUnits(ChronoUnit.DAYS, ChronoUnit.YEARS),
    ChronoField.EPOCH_DAY: FieldUnits(ChronoUnit.DAYS, ChronoUnit.FOREVER),
    ChronoField.ALIGNED_WEEK_OF_MONTH: FieldUnits(ChronoUnit.WEEKS, ChronoUnit.MONTHS),
    ChronoField.ALIGNED_WEEK_OF_YEAR: FieldUnits(ChronoUnit.WEEKS, ChronoUnit.YEARS),
    ChronoField.MONTH_OF_YEAR: FieldUnits(ChronoUnit.MONTHS, ChronoUnit.YEARS),
    ChronoField.PROLEPTIC_MONTH: FieldUnits(ChronoUnit.MONTHS, ChronoUnit.FOREVER),
    ChronoField.YEAR_OF_ERA: FieldUnits(ChronoUnit.YEARS, ChronoUnit.FOREVER),
    ChronoField.YEAR: FieldUnits(ChronoUnit.YEARS, ChronoUnit.FOREVER),
    ChronoField.ERA: FieldUnits(ChronoUnit.ERAS, ChronoUnit.FOREVER),
    ChronoField.INSTANT_SECONDS: FieldUnits(ChronoUnit.SECONDS, ChronoUnit.FOREVER),
    ChronoField.OFFSET_SECONDS: FieldUnits(ChronoUnit.SECONDS, ChronoUnit.FOREVER),
];

/// The smallest unit applied by this field.
ChronoUnit getBaseUnit(ChronoField field) pure nothrow @nogc
{
    return units[field].base;
}

/// The unit covered by the field's full span.
ChronoUnit getRangeUnit(ChronoField field) pure nothrow @nogc
{
    return units[field].span;
}
