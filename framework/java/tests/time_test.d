module flint.java.time_test;

import core.memory : GC;
import flint.java.lang : ArithmeticException, IllegalArgumentException;
import flint.java.time : DateTimeException, DayOfWeek, Duration, Instant, LocalDate, LocalDateTime,
    LocalTime, Month, OffsetDateTime, ZoneId, ZoneOffset, ZonedDateTime, getValue, isLeap;
import flint.java.time.format : DateTimeFormatter, DateTimeFormatterBuilder, DateTimeParseException, TextStyle;

@safe:

private string[][] rows(string tsv) pure
{
    import std.array : split;
    import std.string : lineSplitter;

    string[][] result;
    foreach (line; tsv.lineSplitter)
        if (line.length)
            result ~= line.split("\t");
    return result;
}

// The values GoldenTime.java writes, by label.
private string[2] goldenValue(string label)
{
    const string[2]delegate() @safe[string] table = [
        "date": () => value(LocalDate.of(2010, 9, 7), DateTimeFormatter.ISO_LOCAL_DATE),
        "date_min4": () => value(LocalDate.of(1, 1, 1), DateTimeFormatter.ISO_LOCAL_DATE),
        "date_leap": () => value(LocalDate.of(2024, 2, 29), DateTimeFormatter.ISO_LOCAL_DATE),
        "date_big": () => value(LocalDate.of(10_000, 1, 1), DateTimeFormatter.ISO_LOCAL_DATE),
        "date_neg": () => value(LocalDate.of(-1, 12, 31), DateTimeFormatter.ISO_LOCAL_DATE),
        "time_hm": () => value(LocalTime.of(10, 15), DateTimeFormatter.ISO_LOCAL_TIME),
        "time_hms": () => value(LocalTime.of(10, 15, 30), DateTimeFormatter.ISO_LOCAL_TIME),
        "time_milli": () => value(LocalTime.of(10, 15, 30, 100_000_000),
                DateTimeFormatter.ISO_LOCAL_TIME),
        "time_milli3": () => value(LocalTime.of(10, 15, 30, 123_000_000),
                DateTimeFormatter.ISO_LOCAL_TIME),
        "time_micro": () => value(LocalTime.of(10, 15, 30, 123_456_000),
                DateTimeFormatter.ISO_LOCAL_TIME),
        "time_nano": () => value(LocalTime.of(10, 15, 30, 123_456_789),
                DateTimeFormatter.ISO_LOCAL_TIME),
        "time_midnight": () => value(LocalTime.MIDNIGHT, DateTimeFormatter.ISO_LOCAL_TIME),
        "time_max": () => value(LocalTime.MAX, DateTimeFormatter.ISO_LOCAL_TIME),
        "datetime": () => value(LocalDateTime.of(2013, 1, 1, 9, 30),
                DateTimeFormatter.ISO_LOCAL_DATE_TIME),
        "datetime_nano": () => value(LocalDateTime.of(2013, 1, 1, 9, 30, 5, 7000),
                DateTimeFormatter.ISO_LOCAL_DATE_TIME),
    ];
    if (auto entry = label in table)
        return (*entry)();
    return goldenValue2(label);
}

private string[2] goldenValue2(string label)
{
    const string[2]delegate() @safe[string] table = [
        "instant_epoch": () => value(Instant.EPOCH, DateTimeFormatter.ISO_INSTANT),
        "instant": () => value(Instant.ofEpochSecond(1_700_000_000L, 123_000_000),
                DateTimeFormatter.ISO_INSTANT),
        "instant_whole": () => value(Instant.ofEpochSecond(1_700_000_000L),
                DateTimeFormatter.ISO_INSTANT),
        "instant_nano": () => value(Instant.ofEpochSecond(-1L, 999_999_999),
                DateTimeFormatter.ISO_INSTANT),
        "offset_utc": () => value(OffsetDateTime.of(2026, 11, 23, 5, 51, 34, 123_000_000,
                ZoneOffset.UTC), DateTimeFormatter.ISO_OFFSET_DATE_TIME),
        "offset_plus": () => value(OffsetDateTime.of(2026, 11, 23, 5, 51, 34, 0,
                ZoneOffset.ofHours(2)), DateTimeFormatter.ISO_OFFSET_DATE_TIME),
        "offset_minus": () => value(OffsetDateTime.of(2026, 11, 23, 5, 51, 0, 0,
                ZoneOffset.ofHoursMinutes(-5, -30)), DateTimeFormatter.ISO_OFFSET_DATE_TIME),
        "zoned_offset": () => value(ZonedDateTime.of(2026, 11, 23, 5, 51, 34, 0,
                ZoneOffset.ofHours(1)), DateTimeFormatter.ISO_OFFSET_DATE_TIME),
        "zoned_utc": () => value(ZonedDateTime.of(2026, 11, 23, 5, 51, 34, 0, ZoneOffset.UTC),
                DateTimeFormatter.ISO_OFFSET_DATE_TIME), "duration_zero": () => plain(Duration.ZERO),
        "duration": () => plain(Duration.ofHours(8).plusMinutes(6).plusSeconds(12).plusMillis(345)),
        "duration_neg": () => plain(Duration.ofMillis(-1500)),
        "duration_day": () => plain(Duration.ofDays(1)),
        "duration_neg_frac": () => plain(Duration.ofSeconds(-1, 999_999_999)),
        "duration_nanos": () => plain(Duration.ofNanos(1)),
        "zoneoffset": () => plain(ZoneOffset.ofHoursMinutesSeconds(1, 0, 30)),
        "zoneoffset_utc": () => plain(ZoneOffset.UTC),
    ];
    if (auto entry = label in table)
        return (*entry)();
    assert(false, label);
}

private string[2] value(T)(T v, DateTimeFormatter iso)
{
    return [v.toString(), `"` ~ iso.format(v) ~ `"`];
}

private string[2] plain(T)(T v)
{
    return [v.toString(), `"` ~ v.toString() ~ `"`];
}

@("java.time: toString and the ISO formatters Jackson writes match JDK 21 and Jackson 3.1.8 (time.tsv)")
unittest
{
    auto golden = rows(import("time.tsv"));
    assert(golden.length == 32);
    foreach (row; golden)
    {
        const got = goldenValue(row[0]);
        assert(got[0] == row[1], row[0] ~ ": toString " ~ got[0] ~ " != " ~ row[1]);
        assert(got[1] == row[2], row[0] ~ ": ISO " ~ got[1] ~ " != " ~ row[2]);
    }
}

private DateTimeFormatter formatterNamed(string name)
{
    const DateTimeFormatter delegate() @safe[string] table = [
        "ISO_LOCAL_DATE": () => DateTimeFormatter.ISO_LOCAL_DATE,
        "ISO_LOCAL_TIME": () => DateTimeFormatter.ISO_LOCAL_TIME,
        "ISO_LOCAL_DATE_TIME": () => DateTimeFormatter.ISO_LOCAL_DATE_TIME,
        "ISO_OFFSET_DATE_TIME": () => DateTimeFormatter.ISO_OFFSET_DATE_TIME,
        "ISO_ZONED_DATE_TIME": () => DateTimeFormatter.ISO_ZONED_DATE_TIME,
        "ISO_DATE_TIME": () => DateTimeFormatter.ISO_DATE_TIME,
        "ISO_DATE": () => DateTimeFormatter.ISO_DATE, "ISO_TIME": () => DateTimeFormatter.ISO_TIME,
        "ISO_INSTANT": () => DateTimeFormatter.ISO_INSTANT,
        "BASIC_ISO_DATE": () => DateTimeFormatter.BASIC_ISO_DATE,
    ];
    if (auto entry = name in table)
        return (*entry)();
    return DateTimeFormatter.ofPattern(name);
}

private string formatKind(DateTimeFormatter f, string kind)
{
    const date = LocalDate.of(2010, 9, 7);
    const time = LocalTime.of(14, 5, 9, 120_000_000);
    const ldt = LocalDateTime.of(date, time);
    const odt = OffsetDateTime.of(ldt, ZoneOffset.ofHoursMinutes(5, 30));
    const string delegate() @safe[string] table = [
        "LocalDate": () => f.format(date), "LocalTime": () => f.format(time),
        "LocalDateTime": () => f.format(ldt), "OffsetDateTime": () => f.format(odt),
        "OffsetDateTimeUtc": () => f.format(OffsetDateTime.of(ldt, ZoneOffset.UTC)),
        "ZonedDateTimeUtc": () => f.format(ZonedDateTime.of(ldt, ZoneId.of("UTC"))),
        "ZonedDateTimePlus": () => f.format(ZonedDateTime.of(ldt, ZoneId.of("UTC+2"))),
        "Instant": () => f.format(odt.toInstant()),
        "LocalDateBig": () => f.format(LocalDate.of(12_345, 1, 2)),
        "LocalDateNeg": () => f.format(LocalDate.of(-44, 3, 15)),
        "LocalTimeMidnight": () => f.format(LocalTime.MIDNIGHT),
        "LocalTimeNano": () => f.format(LocalTime.of(0, 0, 0, 1)),
    ];
    if (auto entry = kind in table)
        return (*entry)();
    assert(false, kind);
}

private string parseKind(string kind, string name, string text)
{
    const string delegate() @safe[string] table = [
        "LocalDate": () => LocalDate.parse(text, formatterNamed(name)).toString(),
        "LocalTime": () => LocalTime.parse(text, formatterNamed(name)).toString(),
        "LocalDateTime": () => LocalDateTime.parse(text, formatterNamed(name)).toString(),
        "OffsetDateTime": () => OffsetDateTime.parse(text, formatterNamed(name)).toString(),
        "ZonedDateTime": () => ZonedDateTime.parse(text, formatterNamed(name)).toString(),
        "Instant": () => Instant.parse(text).toString(),
        "Duration": () => Duration.parse(text).toString(),
        "ZoneOffset": () => ZoneOffset.of(text).toString(), "ZoneId": () => ZoneId.of(text).toString(),
    ];
    if (auto entry = kind in table)
        return (*entry)();
    assert(false, kind);
}

@("java.time.format: ISO constants and ofPattern format, parse and fail like JDK 21 (time_format.tsv)")
unittest
{
    size_t formats, parses;
    foreach (row; rows(import("time_format.tsv")))
    {
        string got;
        if (row[0] == "describe")
        {
            got = formatterNamed(row[1]).toString();
            assert(got == row[3], row[1] ~ ": " ~ got ~ " != " ~ row[3]);
        }
        else if (row[0] == "format")
        {
            try
                got = formatKind(formatterNamed(row[1]), row[2]);
            catch (DateTimeException e)
                got = "!" ~ e.msg;
            assert(got == row[3], row[1] ~ " / " ~ row[2] ~ ": " ~ got ~ " != " ~ row[3]);
            ++formats;
        }
        else
        {
            const text = row.length > 3 ? row[3] : "";
            const expected = row.length > 4 ? row[4] : row[3];
            try
                got = parseKind(row[1], row[2], row.length > 4 ? text : "");
            catch (DateTimeException e)
                got = "!" ~ e.msg;
            assert(got == (row.length > 4 ? expected : row[3]),
                    row[1] ~ " " ~ row[2] ~ " '" ~ text ~ "': " ~ got ~ " != " ~ (row.length > 4 ? expected : row[3]));
            ++parses;
        }
    }
    assert(formats == 37 * 12 && parses > 90);
}

@("java.time: epoch-day arithmetic agrees with a day-by-day walk over 1600-2400 and the extremes")
unittest
{
    auto date = LocalDate.of(1600, 1, 1);
    long epochDay = date.toEpochDay();
    int dayOfWeek = date.getDayOfWeek();
    while (date.getYear() < 2401)
    {
        assert(LocalDate.ofEpochDay(epochDay) == date);
        assert(date.getDayOfWeek() == dayOfWeek);
        const last = date.getDayOfMonth() == date.lengthOfMonth();
        if (last && date.getMonthValue() == 12)
            date = LocalDate.of(date.getYear() + 1, 1, 1);
        else if (last)
            date = LocalDate.of(date.getYear(), date.getMonthValue() + 1, 1);
        else
            date = LocalDate.of(date.getYear(), date.getMonthValue(), date.getDayOfMonth() + 1);
        ++epochDay;
        dayOfWeek = (dayOfWeek + 1) % 7;
    }
    assert(LocalDate.EPOCH.toEpochDay() == 0);
    assert(LocalDate.MIN.toEpochDay() == -365_243_219_162L);
    assert(LocalDate.MAX.toEpochDay() == 365_241_780_471L);
    assert(LocalDate.ofEpochDay(-365_243_219_162L) == LocalDate.MIN);
    assert(LocalDate.of(2000, 2, 29).getDayOfYear() == 60 && isLeap(2000) && !isLeap(1900));
}

@("java.time: LocalDate arithmetic clamps to month ends and validates fields")
unittest
{
    assert(LocalDate.of(2024, 1, 31).plusMonths(1) == LocalDate.of(2024, 2, 29));
    assert(LocalDate.of(2024, 2, 29).plusYears(1) == LocalDate.of(2025, 2, 28));
    assert(LocalDate.of(2024, 3, 31).minusMonths(13) == LocalDate.of(2023, 2, 28));
    assert(LocalDate.of(2010, Month.SEPTEMBER, 7).getDayOfWeek() == DayOfWeek.TUESDAY);
    assert(DayOfWeek.TUESDAY.getValue() == 2 && Month.SEPTEMBER.getValue() == 9);
    assert(LocalDate.of(2010, 9, 7).plusDays(-7).isBefore(LocalDate.of(2010, 9, 7)));
    assert(LocalDate.ofYearDay(2024, 366) == LocalDate.of(2024, 12, 31));
    try
    {
        LocalDate.of(2010, 4, 31);
        assert(false);
    }
    catch (DateTimeException e)
        assert(e.msg == "Invalid date 'APRIL 31'");
    try
    {
        LocalTime.of(10, 60);
        assert(false);
    }
    catch (DateTimeException e)
        assert(e.msg == "Invalid value for MinuteOfHour (valid values 0 - 59): 60");
    assert(LocalDate.of(2010, 9, 7).hashCode() == (2010 & 0xFFFFF800 ^ ((2010 << 11) + (9 << 6) + 7)));
}

@("java.time: time and date-time arithmetic wraps and carries")
unittest
{
    assert(LocalTime.of(23, 30).plusHours(2) == LocalTime.of(1, 30));
    assert(LocalTime.of(0, 0).minusSeconds(1) == LocalTime.of(23, 59, 59));
    assert(LocalTime.of(0, 0).plusNanos(-1) == LocalTime.MAX);
    assert(LocalDateTime.of(2010, 12, 31, 23, 59, 59).plusSeconds(1) == LocalDateTime.of(2011, 1, 1, 0, 0));
    assert(LocalDateTime.of(2011, 1, 1, 0, 0).minusMinutes(1) == LocalDateTime.of(2010, 12, 31, 23, 59));
    assert(LocalDateTime.of(2011, 1, 1, 0, 0).plusNanos(-1).toString() == "2010-12-31T23:59:59.999999999");
    const odt = LocalDateTime.of(2010, 9, 7, 10, 15).atOffset(ZoneOffset.ofHours(2));
    assert(odt.toInstant().toString() == "2010-09-07T08:15:00Z");
    assert(odt.withOffsetSameInstant(ZoneOffset.UTC).toString() == "2010-09-07T08:15Z");
    // Java adds the offset difference to the local date-time, so plusDays' year-end check reports Year, not EpochDay.
    // ZoneOffset.compareTo sorts the larger offset first and returns the difference of the total seconds.
    assert(ZoneOffset.ofHours(1).compareTo(ZoneOffset.UTC) == -3600);
    assert(ZoneOffset.MIN.compareTo(ZoneOffset.MAX) == 129_600);
    const edge = OffsetDateTime.of(LocalDateTime.MAX, ZoneOffset.UTC);
    assert(edge.withOffsetSameInstant(ZoneOffset.UTC) == edge);
    try
    {
        edge.withOffsetSameInstant(ZoneOffset.ofHours(1));
        assert(false);
    }
    catch (DateTimeException e)
        assert(e.msg == "Invalid value for Year (valid values -999999999 - 999999999): 1000000000", e.msg);
    assert(odt.atZoneSameInstant(ZoneId.of("UTC")).toString() == "2010-09-07T08:15Z[UTC]");
    assert(odt.isBefore(LocalDateTime.of(2010, 9, 7, 9, 15).atOffset(ZoneOffset.UTC)));
}

@("java.time: compareTo returns the differences Java returns")
unittest
{
    // LocalDate (and so LocalDateTime) returns the first differing year, month or day difference; LocalTime -1/0/1.
    assert(LocalDate.of(2024, 3, 15).compareTo(LocalDate.of(2020, 12, 31)) == 4);
    assert(LocalDate.of(2024, 3, 15).compareTo(LocalDate.of(2024, 7, 1)) == -4);
    assert(LocalDate.of(2024, 3, 15).compareTo(LocalDate.of(2024, 3, 31)) == -16);
    assert(LocalDate.MIN.compareTo(LocalDate.MAX) == -1_999_999_998);
    assert(LocalDateTime.of(2024, 3, 15, 10, 0).compareTo(LocalDateTime.of(2024, 3, 10, 23, 0)) == 5);
    assert(LocalDateTime.of(2024, 3, 15, 8, 0).compareTo(LocalDateTime.of(2024, 3, 15, 10, 0)) == -1);
    // Instant and Duration: -1 or 1 for different seconds, otherwise the nanosecond difference.
    assert(Instant.ofEpochSecond(5, 700).compareTo(Instant.ofEpochSecond(5, 200)) == 500);
    assert(Instant.ofEpochSecond(4, 999_999_999).compareTo(Instant.ofEpochSecond(5)) == -1);
    assert(Duration.ofSeconds(1, 999_999_999).compareTo(Duration.ofSeconds(1)) == 999_999_999);
    assert(Duration.ofSeconds(long.min).compareTo(Duration.ofSeconds(long.max)) == -1);
    // OffsetDateTime: equal offsets compare the local date-times; otherwise the instant, then the local date-time.
    const plus2 = ZoneOffset.ofHours(2);
    assert(OffsetDateTime.of(LocalDateTime.of(2024, 3, 15, 10, 0), plus2)
            .compareTo(OffsetDateTime.of(LocalDateTime.of(2024, 1, 15, 10, 0), plus2)) == 2);
    assert(OffsetDateTime.of(LocalDateTime.of(2024, 3, 15, 10, 0, 0, 500), plus2)
            .compareTo(OffsetDateTime.of(LocalDateTime.of(2024, 3, 15, 8, 0, 0, 100), ZoneOffset.UTC)) == 400);
    assert(OffsetDateTime.of(LocalDateTime.of(2024, 3, 15, 10, 0), plus2)
            .compareTo(OffsetDateTime.of(LocalDateTime.of(2024, 3, 15, 8, 0), ZoneOffset.UTC)) == 1);
}

@("java.time: Instant and Duration arithmetic")
unittest
{
    assert(Instant.ofEpochMilli(-1).toString() == "1969-12-31T23:59:59.999Z");
    assert(Instant.ofEpochSecond(0, -1) == Instant.ofEpochSecond(-1, 999_999_999));
    assert(Instant.ofEpochSecond(10).plus(Duration.ofMillis(1500)).toEpochMilli() == 11_500);
    assert(Duration.between(Instant.ofEpochSecond(10), Instant.ofEpochSecond(8, 500_000_000)).toString() == "PT-1.5S");
    assert(Duration.ofMinutes(90).toHours() == 1 && Duration.ofMillis(-1500).abs().toMillis() == 1500);
    assert(Duration.ofSeconds(-1, 999_999_999).negated() == Duration.ofNanos(1));
    assert(Duration.between(LocalTime.of(10, 0), LocalTime.of(9, 30)) == Duration.ofMinutes(-30));
    assert(Duration.parse(Duration.ofDays(3).plusMillis(7).toString()) == Duration.ofDays(3).plusMillis(7));
}

@("java.time: Duration nanoseconds respect both signed long endpoints")
unittest
{
    assert(Duration.ofSeconds(-9_223_372_037L, 145_224_192).toNanos() == long.min);
    assert(Duration.ofSeconds(9_223_372_036L, 854_775_807).toNanos() == long.max);
    const negativeNano = Duration.ofSeconds(-1, 999_999_999);
    const before = GC.stats().allocatedInCurrentThread;
    assert(negativeNano.toNanos() == -1);
    assert(GC.stats().allocatedInCurrentThread == before);
    foreach (duration; [
        Duration.ofSeconds(-9_223_372_037L, 145_224_191),
        Duration.ofSeconds(9_223_372_036L, 854_775_808), Duration.ofSeconds(long.min),
        Duration.ofSeconds(long.max)
    ])
    {
        try
        {
            duration.toNanos();
            assert(false, "Duration.toNanos must reject overflow");
        }
        catch (ArithmeticException)
        {
        }
    }
}

@("java.time: Duration milliseconds truncate toward zero and check overflow")
unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    assert(Duration.ofNanos(-1).toMillis() == 0);
    assert(Duration.ofNanos(-1_000_001).toMillis() == -1);
    assert(Duration.ofSeconds(-1, 1).toMillis() == -999);
    assert(Duration.ofSeconds(-9_223_372_036_854_776L, 191_000_001).toMillis() == long.min);
    assert(Duration.ofSeconds(9_223_372_036_854_775L, 807_999_999).toMillis() == long.max);
    assert(GC.stats().allocatedInCurrentThread == before);

    foreach (duration; [
        Duration.ofSeconds(-9_223_372_036_854_776L, 191_000_000),
        Duration.ofSeconds(9_223_372_036_854_775L, 808_000_000), Duration.ofSeconds(long.min),
        Duration.ofSeconds(long.max)
    ])
    {
        try
        {
            duration.toMillis();
            assert(false, "Duration.toMillis must reject overflow");
        }
        catch (ArithmeticException error)
        {
            assert(error.msg == "long overflow");
        }
    }
}

@("java.time: now() reads the system clock in UTC")
unittest
{
    const before = Instant.now();
    const today = LocalDate.now();
    const after = Instant.now();
    assert(!after.isBefore(before));
    assert(before.getEpochSecond() > 1_700_000_000L);
    const day = today.toEpochDay();
    assert(day >= before.getEpochSecond() / 86_400 && day <= after.getEpochSecond() / 86_400);
    assert(ZonedDateTime.now().getZone().getId() == "UTC");
    assert(OffsetDateTime.now().getOffset() == ZoneOffset.UTC);
}

@("java.time: zone IDs are fixed offsets; region IDs are refused until the time-zone database is ported")
unittest
{
    assert(ZoneId.systemDefault().getId() == "UTC");
    assert(ZoneId.of("UTC+2").offset() == ZoneOffset.ofHours(2));
    try
    {
        ZoneId.of("Europe/Paris");
        assert(false);
    }
    catch (DateTimeException e)
        assert(e.msg[0 .. 30] == "Unknown time-zone ID: Europe/P");
    assert(DateTimeFormatter.ofPattern("G yyyy").format(LocalDate.of(2024, 3, 5)) == "AD 2024");
    try
    {
        LocalDate.parse("2010-13-01");
        assert(false);
    }
    catch (DateTimeParseException e)
        assert(e.getParsedString() == "2010-13-01" && e.getErrorIndex() == 0);
    try
    {
        LocalDate.parse("2010-9-07");
        assert(false);
    }
    catch (DateTimeParseException e)
        assert(e.getErrorIndex() == 5);
}

@("java.time parses from any characters: nothing keeps the text, an error copies it")
unittest
{
    import flint.java.time : Instant, LocalDate, LocalDateTime, LocalTime;
    import flint.java.time.format : DateTimeFormatter, DateTimeParseException;

    char[] buffer = "2026-01-15".dup;
    const date = LocalDate.parse(buffer);
    buffer[] = 'x';
    assert(date == LocalDate.of(2026, 1, 15));

    buffer = "10:15:30".dup;
    const time = LocalTime.parse(buffer);
    buffer[] = '0';
    assert(time == LocalTime.of(10, 15, 30));

    buffer = "2026-01-15T10:15".dup;
    const dateTime = LocalDateTime.parse(buffer, DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    buffer[] = '9';
    assert(dateTime == LocalDateTime.of(2026, 1, 15, 10, 15));

    buffer = "2026-01-15T10:15:30Z".dup;
    const instant = Instant.parse(buffer);
    buffer[] = '1';
    assert(instant == Instant.parse("2026-01-15T10:15:30Z"));

    buffer = "2026-13-01".dup;
    try
    {
        LocalDate.parse(buffer);
        assert(false);
    }
    catch (DateTimeParseException e)
    {
        buffer[] = '#';
        assert(e.getParsedString() == "2026-13-01" && e.msg[0 .. 18] == "Text '2026-13-01' ", e.msg);
    }
}

@("java.time formatter parse errors report UTF-16 offsets after Unicode literals")
unittest
{
    const formatter = DateTimeFormatter.ofPattern("'é😀'uuuu-MM-dd");
    assert(LocalDate.parse("é😀2026-01-15", formatter) == LocalDate.of(2026, 1, 15));

    try
    {
        formatter.parse("é😀2026-x1-15");
        assert(false);
    }
    catch (DateTimeParseException e)
    {
        assert(e.getErrorIndex() == 8, e.msg);
        assert(e.msg == "Text 'é😀2026-x1-15' could not be parsed at index 8", e.msg);
    }

    try
    {
        formatter.parse("é😀2026-01-15!");
        assert(false);
    }
    catch (DateTimeParseException e)
    {
        assert(e.getErrorIndex() == 13, e.msg);
        assert(e.msg == "Text 'é😀2026-01-15!' could not be parsed, unparsed text found at index 13", e.msg);
    }
}

@("ISO offset date and time require minutes and keep optional offset seconds")
unittest
{
    import std.exception : collectException;

    const date = DateTimeFormatter.ISO_OFFSET_DATE;
    const time = DateTimeFormatter.ISO_OFFSET_TIME;
    const text = "2000-02-29T10:15:30.125-05:30:15";
    const value = OffsetDateTime.parse(text);
    assert(date.format(value) == "2000-02-29-05:30:15");
    assert(time.format(value) == "10:15:30.125-05:30:15");
    assert(date.format(OffsetDateTime.parse("+12000-02-29T10:15:30Z")) == "+12000-02-29Z");
    assert(time.format(OffsetDateTime.parse("2000-02-29T10:15:30Z")) == "10:15:30Z");

    assert(date.toString() == "ParseCaseSensitive(false)(Value(Year,4,10,EXCEEDS_PAD)'-'"
            ~ "Value(MonthOfYear,2)'-'Value(DayOfMonth,2))Offset(+HH:MM:ss,'Z')");
    assert(time.toString() == "ParseCaseSensitive(false)(Value(HourOfDay,2)':'Value(MinuteOfHour,2)"
            ~ "[':'Value(SecondOfMinute,2)[Fraction(NanoOfSecond,0,9,DecimalPoint)]])Offset(+HH:MM:ss,'Z')");
    assert(LocalDate.parse("2000-02-29z", date) == LocalDate.of(2000, 2, 29));
    assert(LocalTime.parse("23:59Z", time) == LocalTime.of(23, 59));
    assert(date.parse("2000-02-29-05:30:15").toOffset(text).getTotalSeconds() == -19_815);
    assert(time.parse("10:15:30.125+18:00").toOffset(text).getTotalSeconds() == 64_800);

    const extraOffset = date.parse("2000-02-29+19:00");
    assert(extraOffset.hasOffset());
    assert(collectException!DateTimeParseException(extraOffset.toOffset("2000-02-29+19:00")) !is null);
    assert(collectException!DateTimeParseException(LocalDate.parse("1900-02-29Z", date)).getErrorIndex() == 0);
    assert(collectException!DateTimeParseException(LocalTime.parse("24:00Z", time)).getErrorIndex() == 0);

    foreach (input; ["2000-02-29+01", "2000-02-29+0100", "2000-02-29+02:60", "2000-02-29"])
    {
        auto failure = collectException!DateTimeParseException(date.parse(input));
        assert(failure !is null && failure.getErrorIndex() == 10);
    }
    foreach (input; ["10:15:30.125+01", "10:15:30.125+0100", "10:15:30.125"])
    {
        auto failure = collectException!DateTimeParseException(time.parse(input));
        assert(failure !is null && failure.getErrorIndex() == 12);
    }
}

@("ISO ordinal dates resolve the day of year and accept an optional strict offset")
unittest
{
    import std.exception : collectException;

    const formatter = DateTimeFormatter.ISO_ORDINAL_DATE;
    assert(formatter.toString() == "ParseCaseSensitive(false)Value(Year,4,10,EXCEEDS_PAD)'-'"
            ~ "Value(DayOfYear,3)[Offset(+HH:MM:ss,'Z')]");
    assert(formatter.format(LocalDate.of(2024, 12, 31)) == "2024-366");
    assert(formatter.format(LocalDate.of(-4, 12, 31)) == "-0004-366");
    assert(formatter.format(LocalDate.of(12_000, 12, 31)) == "+12000-366");
    const offsetValue = OffsetDateTime.parse("2024-02-29T08:09:10-05:30:15");
    assert(formatter.format(offsetValue) == "2024-060-05:30:15");

    assert(LocalDate.parse("2024-001", formatter) == LocalDate.of(2024, 1, 1));
    assert(LocalDate.parse("2024-366", formatter) == LocalDate.of(2024, 12, 31));
    assert(LocalDate.parse("-0004-366", formatter) == LocalDate.of(-4, 12, 31));
    assert(LocalDate.parse("2024-060z", formatter) == LocalDate.of(2024, 2, 29));
    assert(!formatter.parse("2024-060").hasOffset());
    const withOffset = "2024-060-05:30:15";
    assert(formatter.parse(withOffset).toOffset(withOffset).getTotalSeconds() == -19_815);
    assert(formatter.parse("2024-060+19:00").hasOffset());

    foreach (text; ["2023-366", "2024-367", "2024-000"])
    {
        auto error = collectException!DateTimeParseException(LocalDate.parse(text, formatter));
        assert(error !is null && error.getErrorIndex() == 0);
    }
    foreach (text; ["2024-060+01", "2024-060+0100", "2024-060+02:60"])
    {
        auto error = collectException!DateTimeParseException(formatter.parse(text));
        assert(error !is null && error.getErrorIndex() == 8);
    }
}

@("DateTimeFormatter applies the zone override to offset and zoned values")
unittest
{
    const zone = ZoneId.of("-04:00");
    const iso = DateTimeFormatter.ISO_OFFSET_DATE_TIME.withZone(zone);
    const pattern = DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss XXX VV").withZone(zone);
    const offset = OffsetDateTime.parse("2024-03-01T01:30:10.125+05:30");
    const zoned = offset.toInstant().atZone(ZoneId.of("+05:30"));
    assert(iso.format(offset) == "2024-02-29T16:00:10.125-04:00");
    assert(iso.format(zoned) == "2024-02-29T16:00:10.125-04:00");
    assert(iso.format(offset.toInstant()) == "2024-02-29T16:00:10.125-04:00");
    assert(pattern.format(offset) == "2024-02-29 16:00:10 -04:00 -04:00");
    assert(pattern.format(zoned) == "2024-02-29 16:00:10 -04:00 -04:00");
    assert(DateTimeFormatter.ISO_INSTANT.withZone(zone).format(offset) == "2024-02-29T20:00:10.125Z");
    const local = LocalDateTime.parse("2024-03-01T01:30:10.125");
    assert(DateTimeFormatter.ISO_LOCAL_DATE_TIME.withZone(zone).format(local) == "2024-03-01T01:30:10.125");
}

@("ISO date and time optional offsets require both minute digits")
unittest
{
    import std.exception : collectException;

    struct OptionalOffsetCase
    {
        DateTimeFormatter formatter;
        string prefix;
    }

    const cases = [
        OptionalOffsetCase(DateTimeFormatter.ISO_DATE, "2024-03-31"),
        OptionalOffsetCase(DateTimeFormatter.ISO_TIME, "01:02:03"),
        OptionalOffsetCase(DateTimeFormatter.ISO_DATE_TIME, "2024-03-31T01:02:03"),
    ];
    foreach (example; cases)
    {
        foreach (suffix; ["+01", "+0100", "+010030", "+00", "+01:", "+01:0"])
        {
            const text = example.prefix ~ suffix;
            const error = collectException!DateTimeParseException(example.formatter.parse(text));
            assert(error !is null && error.getErrorIndex() == example.prefix.length, text);
        }

        assert(!example.formatter.parse(example.prefix).hasOffset());
        const zero = example.prefix ~ "z";
        assert(example.formatter.parse(zero).toOffset(zero).getTotalSeconds() == 0);
        const offset = example.prefix ~ "+01:00:30";
        assert(example.formatter.parse(offset).toOffset(offset).getTotalSeconds() == 3_630);
    }

    const zoned = "2024-03-31T01:02:03+01:00[UTC]";
    assert(DateTimeFormatter.ISO_DATE_TIME.parse(zoned).zoneId() == "UTC");

    const offsetDateTime = "2024-03-31T01:02:03+01";
    assert(DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse(offsetDateTime).toOffset(offsetDateTime)
            .getTotalSeconds() == 3_600);
    const basicDate = "20240331+0100";
    assert(DateTimeFormatter.BASIC_ISO_DATE.parse(basicDate).toOffset(basicDate).getTotalSeconds() == 3_600);
}

@("DateTimeFormatter prints a local override zone without creating an offset")
unittest
{
    import std.exception : collectException;

    const offset = ZoneId.of("+05:45");
    const named = ZoneId.of("UTC");
    const local = LocalDateTime.parse("2024-03-31T02:15:30");
    const date = local.toLocalDate();
    const time = local.toLocalTime();

    assert(DateTimeFormatter.ofPattern("uuuu-MM-dd VV").withZone(offset).format(date) == "2024-03-31 +05:45");
    assert(DateTimeFormatter.ofPattern("HH:mm:ss VV").withZone(named).format(time) == "02:15:30 UTC");
    const formatter = DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss VV");
    assert(formatter.withZone(offset).format(local) == "2024-03-31 02:15:30 +05:45");
    assert(formatter.withZone(named).format(local) == "2024-03-31 02:15:30 UTC");
    assert(collectException!DateTimeException(formatter.format(local)) !is null);

    const optional = DateTimeFormatter.ofPattern("HH:mm[ XXX][ VV]").withZone(offset);
    assert(optional.format(local) == "02:15 +05:45");
    const requiredOffset = DateTimeFormatter.ofPattern("HH:mm XXX").withZone(offset);
    assert(collectException!DateTimeException(requiredOffset.format(local)) !is null);
    assert(DateTimeFormatter.ISO_DATE_TIME.withZone(named).format(local) == "2024-03-31T02:15:30");
}

@("DateTimeFormatter clears an absent zone override without losing its pattern")
unittest
{
    import std.exception : collectException;
    import std.typecons : Nullable;

    const text = "2024-03-31T02:15:30";
    const original = DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss[' 'VV]");
    const local = LocalDateTime.parse(text);
    const overridden = original.withZone(ZoneId.of("+05:45"));
    const cleared = overridden.withZone(Nullable!ZoneId.init);

    assert(original.getZone().isNull);
    assert(overridden.getZone().get().getId() == "+05:45");
    assert(cleared.getZone().isNull);
    assert(cleared.toString() == original.toString());
    assert(cleared.format(local) == original.format(local));
    assert(LocalDateTime.parse(text, cleared) == local);
    assert(overridden.format(local) == text ~ " +05:45");
    const instant = Instant.parse("2024-03-31T00:15:30Z");
    assert(overridden.format(instant) == "2024-03-31T06:00:30 +05:45");
    assert(collectException!DateTimeException(cleared.format(instant)) !is null);

    const zulu = original.withZone(Nullable!ZoneId(ZoneId.init));
    assert(!zulu.getZone().isNull && zulu.getZone().get().getId() == "Z");
    assert(zulu.format(local) == text ~ " Z");
    assert(zulu.withZone(Nullable!ZoneId.init).getZone().isNull);
    assert(original.withZone(Nullable!ZoneId.init).toString() == original.toString());
}

@("DateTimeFormatter uses a parsed or override zone to resolve zoned date-time")
unittest
{
    import std.exception : collectException;
    import std.typecons : Nullable;

    const text = "2024-03-31T02:15:30";
    const overrideZone = ZoneId.of("+05:45");
    const local = DateTimeFormatter.ISO_LOCAL_DATE_TIME.withZone(overrideZone);
    const fields = local.parse(text);
    assert(fields.zoneId() == "+05:45" && !fields.hasOffset());
    assert(ZonedDateTime.parse(text, local).toString() == text ~ "+05:45");

    const offset = DateTimeFormatter.ISO_OFFSET_DATE_TIME.withZone(overrideZone);
    assert(ZonedDateTime.parse(text ~ "+02:00", offset).toString() == "2024-03-31T06:00:30+05:45");
    const explicitZone = DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss VV");
    assert(ZonedDateTime.parse(text ~ " UTC", explicitZone.withZone(overrideZone)).toString() == text ~ "Z[UTC]");
    assert(ZonedDateTime.parse(text ~ " UTC", explicitZone).toString() == text ~ "Z[UTC]");
    const explicitBoth = DateTimeFormatter.ISO_ZONED_DATE_TIME.withZone(overrideZone);
    assert(ZonedDateTime.parse(text ~ "+02:00[UTC]", explicitBoth).toString() == "2024-03-31T00:15:30Z[UTC]");
    const instant = DateTimeFormatter.ISO_INSTANT.withZone(overrideZone);
    assert(ZonedDateTime.parse("2024-03-31T00:15:30Z", instant).toString() == "2024-03-31T06:00:30+05:45");

    const cleared = local.withZone(Nullable!ZoneId.init);
    assert(collectException!DateTimeParseException(ZonedDateTime.parse(text, cleared)) !is null);
}

// One RFC_1123_DATE_TIME operation of rfc1123.tsv: the result's toString, or `!` and the exception message (and a
// parse exception's error index).
private string rfc1123Result(string kind, string input)
{
    import flint.engine.aot.text : decimal;

    const f = DateTimeFormatter.RFC_1123_DATE_TIME;
    const string delegate() @safe[string] table = [
        "toString": () => f.toString(),
        "formatOffsetDateTime": () => f.format(OffsetDateTime.parse(input)),
        "formatZonedDateTime": () => f.format(ZonedDateTime.parse(input)),
        "formatLocalDateTime": () => f.format(LocalDateTime.parse(input)),
        "formatLocalDate": () => f.format(LocalDate.parse(input)),
        "formatLocalTime": () => f.format(LocalTime.parse(input)),
        "formatInstant": () => f.format(Instant.parse(input)),
        "formatInstantWithZone": () => f.withZone(ZoneOffset.UTC.toZoneId())
            .format(Instant.parse(input)),
        "parseOffsetDateTime": () => OffsetDateTime.parse(input, f).toString(),
        "parseZonedDateTime": () => ZonedDateTime.parse(input, f).toString(),
        "parseLocalDateTime": () => LocalDateTime.parse(input, f).toString(),
        "parseLocalDate": () => LocalDate.parse(input, f).toString(),
        "parseLocalTime": () => LocalTime.parse(input, f).toString(),
    ];
    try
        return table[kind]();
    catch (DateTimeParseException e)
        return "!" ~ e.msg ~ "\t" ~ decimal(e.getErrorIndex());
    catch (DateTimeException e)
        return "!" ~ e.msg;
}

@("RFC_1123_DATE_TIME formats, parses leniently and resolves SMART like JDK 21 (rfc1123.tsv)")
unittest
{
    import std.array : join;

    size_t count;
    foreach (row; rows(import("rfc1123.tsv")))
    {
        const expected = row[2 .. $].join("\t");
        const got = rfc1123Result(row[0], row[1]);
        assert(got == expected, row[0] ~ " '" ~ row[1] ~ "': " ~ got ~ " != " ~ expected);
        ++count;
    }
    assert(count == 629);
}

// One operation of ofpattern_smart.tsv: the result's toString, or `!` and the exception message (and a parse
// exception's error index). A formatter input is `pattern|text` or `CONSTANT|text`.
private string ofPatternSmartResult(string kind, string input)
{
    import flint.engine.aot.text : decimal;

    try
    {
        if (kind == "ofYearDay")
            return ofYearDayResult(input);
        if (kind == "getResolverStyle")
            return resolverStyleResult(input);
        return styledParseResult(kind, input);
    }
    catch (DateTimeParseException e)
        return "!" ~ e.msg ~ "\t" ~ decimal(e.getErrorIndex());
    catch (DateTimeException e)
        return "!" ~ e.msg;
}

// `year,day` through LocalDate.ofYearDay.
private string ofYearDayResult(string input)
{
    import std.conv : to;
    import std.string : indexOf;

    const comma = input.indexOf(',');
    return LocalDate.ofYearDay(input[0 .. comma].to!int, input[comma + 1 .. $].to!int).toString();
}

// The resolver style of `ofPattern`, `ISO_LOCAL_DATE` or `RFC_1123_DATE_TIME`, optionally `/STRICT` or `/SMART`.
private string resolverStyleResult(string input)
{
    import flint.java.time.format : ResolverStyle;
    import std.algorithm.searching : endsWith, startsWith;
    import std.conv : to;

    DateTimeFormatter f = DateTimeFormatter.RFC_1123_DATE_TIME;
    if (input.startsWith("ofPattern"))
        f = DateTimeFormatter.ofPattern("uuuu");
    else if (input.startsWith("ISO"))
        f = DateTimeFormatter.ISO_LOCAL_DATE;
    if (input.endsWith("/STRICT"))
        f = f.withResolverStyle(ResolverStyle.STRICT);
    else if (input.endsWith("/SMART"))
        f = f.withResolverStyle(ResolverStyle.SMART);
    return f.getResolverStyle().to!string;
}

// A parse kind: plain (`parse...`, an ofPattern pattern), `strict...` (the pattern resolved STRICT), `smart...` (an
// ISO constant resolved SMART) or `iso...` (the ISO constant as it is).
private string styledParseResult(string kind, string input)
{
    import flint.java.time.format : ResolverStyle;
    import std.algorithm.searching : startsWith;
    import std.string : indexOf;

    const bar = input.indexOf('|');
    const name = input[0 .. bar], t = input[bar + 1 .. $];
    const DateTimeFormatter[string] iso = [
        "ISO_LOCAL_DATE": DateTimeFormatter.ISO_LOCAL_DATE,
        "ISO_LOCAL_DATE_TIME": DateTimeFormatter.ISO_LOCAL_DATE_TIME,
        "ISO_OFFSET_DATE_TIME": DateTimeFormatter.ISO_OFFSET_DATE_TIME,
        "ISO_LOCAL_TIME": DateTimeFormatter.ISO_LOCAL_TIME,
    ];
    const strict = kind.startsWith("strict"), smart = kind.startsWith("smart"), constant = kind.startsWith("iso");
    DateTimeFormatter f = smart || constant ? iso[name] : DateTimeFormatter.ofPattern(name);
    if (strict)
        f = f.withResolverStyle(ResolverStyle.STRICT);
    else if (smart)
        f = f.withResolverStyle(ResolverStyle.SMART);
    const string delegate() @safe[string] table = [
        "parse": () { f.parse(t); return "parsed"; },
        "parseLocalDate": () => LocalDate.parse(t, f).toString(),
        "parseLocalTime": () => LocalTime.parse(t, f).toString(),
        "parseLocalDateTime": () => LocalDateTime.parse(t, f).toString(),
        "parseOffsetDateTime": () => OffsetDateTime.parse(t, f).toString(),
        "parseZonedDateTime": () => ZonedDateTime.parse(t, f).toString(),
    ];
    const prefix = strict ? 6 : smart ? 5 : constant ? 3 : 0;
    return table["p" ~ kind[prefix + 1 .. $]]();
}

@("ofPattern resolves SMART, withResolverStyle switches styles and ofYearDay checks ranges like JDK 21")
unittest
{
    import std.array : join;

    size_t count;
    foreach (row; rows(import("ofpattern_smart.tsv")))
    {
        const expected = row[2 .. $].join("\t");
        const got = ofPatternSmartResult(row[0], row[1]);
        assert(got == expected, row[0] ~ " '" ~ row[1] ~ "': " ~ got ~ " != " ~ expected);
        ++count;
    }
    assert(count == 694);
}

// One ISO_WEEK_DATE operation of iso_week_date.tsv: the result's toString, or `!` and the exception message (and a
// parse exception's error index). A `smart` prefix parses with the formatter resolved SMART.
private string isoWeekDateResult(string kind, string input)
{
    import flint.engine.aot.text : decimal;
    import flint.java.time.format : ResolverStyle;
    import std.algorithm.searching : startsWith;

    try
    {
        if (!kind.startsWith("smart"))
            return isoWeekDateOperation(DateTimeFormatter.ISO_WEEK_DATE, kind, input);
        const smart = DateTimeFormatter.ISO_WEEK_DATE.withResolverStyle(ResolverStyle.SMART);
        return isoWeekDateOperation(smart, kind[5 .. $], input);
    }
    catch (DateTimeParseException e)
        return "!" ~ e.msg ~ "\t" ~ decimal(e.getErrorIndex());
    catch (DateTimeException e)
        return "!" ~ e.msg;
}

private string isoWeekDateOperation(const DateTimeFormatter f, string kind, string input)
{
    import std.conv : to;

    const string delegate() @safe[string] table = [
        "toString": () => f.toString(), "getResolverStyle": () => f.getResolverStyle().to!string,
        "formatLocalDate": () => f.format(LocalDate.parse(input)),
        "formatLocalDateTime": () => f.format(LocalDateTime.parse(input)),
        "formatOffsetDateTime": () => f.format(OffsetDateTime.parse(input)),
        "formatZonedDateTime": () => f.format(ZonedDateTime.parse(input)),
        "formatLocalTime": () => f.format(LocalTime.parse(input)),
        "formatInstant": () => f.format(Instant.parse(input)),
        "formatInstantWithZone": () => f.withZone(ZoneOffset.UTC.toZoneId()).format(Instant.parse(input)),
        "parse": () { f.parse(input); return "parsed"; },
        "parseLocalDate": () => LocalDate.parse(input, f).toString(),
        "parseLocalDateTime": () => LocalDateTime.parse(input, f).toString(),
        "parseLocalTime": () => LocalTime.parse(input, f).toString(),
        "parseOffsetDateTime": () => OffsetDateTime.parse(input, f).toString(),
    ];
    return table[kind]();
}

@("ISO_WEEK_DATE formats week-based years and resolves weeks STRICT and SMART like JDK 21 (iso_week_date.tsv)")
unittest
{
    import std.array : join;

    size_t count;
    foreach (row; rows(import("iso_week_date.tsv")))
    {
        const expected = row.length > 2 ? row[2 .. $].join("\t") : "";
        const got = isoWeekDateResult(row[0], row[1]);
        assert(got == expected, row[0] ~ " '" ~ row[1] ~ "': " ~ got ~ " != " ~ expected);
        ++count;
    }
    assert(count == 957);
}

// The LocalDateTime operations of epoch_day.tsv, applied to `input` at 10:15:30.
private string dateTimeStep(string kind, string input, long arg)
{
    const value = LocalDate.parse(input).atTime(10, 15, 30);
    const string delegate() @safe[string] table = [
        "dateTimePlusDays": () => value.plusDays(arg).toString(),
        "dateTimeMinusDays": () => value.minusDays(arg).toString(),
        "dateTimePlusWeeks": () => value.plusWeeks(arg).toString(),
        "dateTimePlusHours": () => value.plusHours(arg).toString(),
        "dateTimeMinusHours": () => value.minusHours(arg).toString(),
        "dateTimePlusMinutes": () => value.plusMinutes(arg).toString(),
        "dateTimeMinusMinutes": () => value.minusMinutes(arg).toString(),
        "dateTimePlusSeconds": () => value.plusSeconds(arg).toString(),
        "dateTimeMinusSeconds": () => value.minusSeconds(arg).toString(),
    ];
    return table[kind]();
}

// The LocalDate and epoch operations of epoch_day.tsv.
private string dateStep(string kind, string input, long arg)
{
    LocalDate date() => LocalDate.parse(input);

    const string delegate() @safe[string] table = [
        "ofEpochDay": () => LocalDate.ofEpochDay(arg).toString(),
        "plusDays": () => date().plusDays(arg).toString(),
        "minusDays": () => date().minusDays(arg).toString(),
        "plusWeeks": () => date().plusWeeks(arg).toString(),
        "minusWeeks": () => date().minusWeeks(arg).toString(),
        "plusMonths": () => date().plusMonths(arg).toString(),
        "minusMonths": () => date().minusMonths(arg).toString(),
        "plusYears": () => date().plusYears(arg).toString(),
        "minusYears": () => date().minusYears(arg).toString(),
        "withDayOfMonth": () => date().withDayOfMonth(cast(int) arg).toString(),
        "ofEpochSecondUTC": () => LocalDateTime.ofEpochSecond(arg, 0, ZoneOffset.UTC).toString(),
        "ofEpochSecondPlus2": () => LocalDateTime.ofEpochSecond(arg, 0, ZoneOffset.ofHours(2)).toString(),
    ];
    return table[kind]();
}

// One operation of epoch_day.tsv: the result's toString, or `!`, the exception's class name, `: ` and its message.
private string epochDayResult(string kind, string input, long arg)
{
    import std.algorithm.searching : startsWith;

    try
        return kind.startsWith("dateTime") ? dateTimeStep(kind, input, arg) : dateStep(kind, input, arg);
    catch (DateTimeException e)
        return "!DateTimeException: " ~ e.msg;
    catch (ArithmeticException e)
        return "!ArithmeticException: " ~ e.msg;
}

@("LocalDate and LocalDateTime arithmetic report EpochDay, Year, DayOfMonth and overflow like JDK 21 (epoch_day.tsv)")
unittest
{
    import std.conv : to;

    size_t count;
    foreach (row; rows(import("epoch_day.tsv")))
    {
        const got = epochDayResult(row[0], row[1], row[2].to!long);
        assert(got == row[3], row[0] ~ " '" ~ row[1] ~ "' " ~ row[2] ~ ": " ~ got ~ " != " ~ row[3]);
        ++count;
    }
    assert(count == 7555);
}

@("a STRICT year-of-era pattern does not resolve a date without an era, as in JDK 21")
unittest
{
    import flint.java.time.format : ResolverStyle;
    import std.algorithm.searching : startsWith;
    import std.exception : collectException;

    const strict = DateTimeFormatter.ofPattern("yyyy-MM-dd").withResolverStyle(ResolverStyle.STRICT);
    const e = collectException!DateTimeParseException(LocalDate.parse("2019-11-30", strict));
    assert(e !is null && e.msg.startsWith("Text '2019-11-30' could not be parsed: Unable to obtain LocalDate"));
    assert(LocalDate.parse("2019-11-30", DateTimeFormatter.ofPattern("yyyy-MM-dd")) == LocalDate.of(2019, 11, 30));
    assert(LocalDate.parse("2019-11-30", DateTimeFormatter.ofPattern("uuuu-MM-dd")
            .withResolverStyle(ResolverStyle.STRICT)) == LocalDate.of(2019, 11, 30));
}

@("TextStyle pairs each size's normal and stand-alone forms, and FormatStyle keeps Java's order, as in JDK 21")
unittest
{
    import flint.java.time.format : asNormal, asStandalone, FormatStyle, isStandalone, TextStyle;
    import std.conv : to;

    // JDK 21: ordinal, name, isStandalone(), asStandalone(), asNormal() for each TextStyle.values().
    static immutable string[5][] expected = [
        ["0", "FULL", "false", "FULL_STANDALONE", "FULL"],
        ["1", "FULL_STANDALONE", "true", "FULL_STANDALONE", "FULL"],
        ["2", "SHORT", "false", "SHORT_STANDALONE", "SHORT"],
        ["3", "SHORT_STANDALONE", "true", "SHORT_STANDALONE", "SHORT"],
        ["4", "NARROW", "false", "NARROW_STANDALONE", "NARROW"],
        ["5", "NARROW_STANDALONE", "true", "NARROW_STANDALONE", "NARROW"],
    ];
    size_t count;
    foreach (style; [__traits(allMembers, TextStyle)])
    {
        const s = style.to!TextStyle;
        const row = expected[count++];
        assert(row == [
            (cast(int) s).to!string, s.to!string, s.isStandalone.to!string,
            s.asStandalone.to!string, s.asNormal.to!string
        ], style);
    }
    assert(count == 6);
    assert([__traits(allMembers, FormatStyle)] == ["FULL", "LONG", "MEDIUM", "SHORT"]);
    assert(cast(int) FormatStyle.SHORT == 3);
    static assert(!__traits(compiles, isStandalone(null)));
}

@("DateTimeFormatter.ofLocalizedDate uses the en-US CLDR date patterns and Java's Localized description")
unittest
{
    import flint.java.time.format : DateTimeFormatter, FormatStyle, ResolverStyle;
    import std.exception : collectException;

    // JDK 21 Temurin 21.0.13+9, default format locale en_US: toString and the text of five dates.
    static immutable string[4] names = ["FULL", "LONG", "MEDIUM", "SHORT"];
    static immutable string[5][] expected = [
        [
            "Tuesday, March 5, 2024", "Monday, December 31, 1", "Thursday, June 7, 12345",
            "Saturday, January 1, 1", "Wednesday, February 3, 2"
        ], ["March 5, 2024", "December 31, 1", "June 7, 12345", "January 1, 1", "February 3, 2"],
        ["Mar 5, 2024", "Dec 31, 1", "Jun 7, 12345", "Jan 1, 1", "Feb 3, 2"],
        ["3/5/24", "12/31/01", "6/7/45", "1/1/01", "2/3/02"],
    ];
    const LocalDate[] dates = [
        LocalDate.of(2024, 3, 5), LocalDate.of(1, 12, 31), LocalDate.of(12_345, 6, 7),
        LocalDate.of(0, 1, 1), LocalDate.of(-1, 2, 3),
    ];
    const FormatStyle[] styles = [
        FormatStyle.FULL, FormatStyle.LONG, FormatStyle.MEDIUM, FormatStyle.SHORT
    ];
    foreach (s, style; styles)
    {
        const f = DateTimeFormatter.ofLocalizedDate(style);
        assert(f.toString() == "Localized(" ~ names[s] ~ ",)", f.toString());
        assert(f.getResolverStyle() == ResolverStyle.SMART);
        foreach (i, date; dates)
        {
            const text = expected[s][i];
            assert(f.format(date) == text, text);
            // The patterns name a year of era without an era, and SHORT reduces it, so only 2024 names itself back.
            if (i == 0)
                assert(LocalDate.parse(text, f) == date, text);
        }
    }
    // A strict resolver needs an era, as ofPattern's year-of-era letters do; ofLocalizedDate stays SMART.
    const strict = DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT).withResolverStyle(ResolverStyle.STRICT);
    assert(collectException!DateTimeParseException(LocalDate.parse("3/5/24", strict)) !is null);
    // The short style reads a reduced year-of-era from 2000, case-sensitively, and reads the whole text.
    const shortFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT);
    assert(LocalDate.parse("1/1/70", shortFormatter) == LocalDate.of(2070, 1, 1));
    assert(LocalDate.parse("12/31/01", shortFormatter) == LocalDate.of(2001, 12, 31));
    auto lower = collectException!DateTimeParseException(LocalDate.parse("mar 7, 2024",
            DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)));
    assert(lower !is null && lower.getErrorIndex() == 0);
    auto trailing = collectException!DateTimeParseException(LocalDate.parse("3/7/24x", shortFormatter));
    assert(trailing !is null && trailing.getErrorIndex() == 6);
    // FULL parses the day-of-week and cross-checks it against the date.
    auto conflict = collectException!DateTimeParseException(LocalDate.parse("Wednesday, March 7, 2024",
            DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)));
    assert(conflict !is null && conflict.msg == "Text 'Wednesday, March 7, 2024' could not be parsed: Conflict found: "
            ~ "Field DayOfWeek 4 differs from DayOfWeek 3 derived from 2024-03-07", conflict.msg);
}

@("DecimalStyle keeps four UTF-16 symbols with Java's hash and text, as in JDK 21")
unittest
{
    import flint.java.time.format : DecimalStyle;

    static struct Row
    {
        DecimalStyle style;
        wchar[4] units;
        int hash;
        string text;
        bool standard;
    }

    const s = DecimalStyle.STANDARD;
    // JDK 21 DecimalWitness: code units, hashCode(), toString() and equals(STANDARD).
    // Java's lone U+D800 is written as U+FFFD (R14).
    const Row[] rows = [
        Row(s, ['0', '+', '-', '.'], 182, "DecimalStyle[0+-.]", true),
        Row(s.withZeroDigit('\u0660'), ['\u0660', '+', '-', '.'], 1766,
                "DecimalStyle[\u0660+-.]", false),
        Row(s.withZeroDigit('0'), ['0', '+', '-', '.'], 182, "DecimalStyle[0+-.]", true),
        Row(s.withPositiveSign('p'), ['0', 'p', '-', '.'], 251, "DecimalStyle[0p-.]", false),
        Row(s.withNegativeSign('\u2212'), ['0', '+', '\u2212', '.'], 8859,
                "DecimalStyle[0+\u2212.]", false),
        Row(s.withDecimalSeparator(','), ['0', '+', '-', ','], 180, "DecimalStyle[0+-,]", false),
        Row(s.withZeroDigit('\u0966').withPositiveSign('P').withNegativeSign('N')
                .withDecimalSeparator('\u066B'), ['\u0966', 'P', 'N', '\u066B'], 4207,
                "DecimalStyle[\u0966PN\u066B]", false),
        Row(s.withZeroDigit(cast(wchar) 0xD800), [0xD800, '+', '-', '.'], 55_430,
                "DecimalStyle[\uFFFD+-.]", false),
        Row(s.withZeroDigit(wchar.max).withPositiveSign(wchar.max).withNegativeSign(wchar.max)
                .withDecimalSeparator(wchar.max), [wchar.max, wchar.max, wchar.max, wchar.max],
                262_140, "DecimalStyle[\uFFFF\uFFFF\uFFFF\uFFFF]", false),
        Row(s.withZeroDigit('\0'), ['\0', '+', '-', '.'], 134, "DecimalStyle[\0+-.]", false),
        Row(s.withDecimalSeparator(',').withDecimalSeparator('.'), ['0', '+', '-', '.'], 182,
                "DecimalStyle[0+-.]", true),
    ];
    foreach (i, row; rows)
    {
        const d = row.style;
        const wchar[4] units = [
            d.getZeroDigit, d.getPositiveSign, d.getNegativeSign, d.getDecimalSeparator
        ];
        assert(units == row.units, row.text);
        assert(d.hashCode == row.hash, row.text);
        assert(d.toString == row.text, row.text);
        assert(d.equals(DecimalStyle.STANDARD) == row.standard, row.text);
        assert((d == DecimalStyle.STANDARD) == row.standard, row.text);
    }
    assert(DecimalStyle.init == DecimalStyle.STANDARD);
    assert(s.withDecimalSeparator(',').equals(s.withDecimalSeparator(',')));
    static assert(!__traits(compiles, DecimalStyle('1', '+', '-', '.')));
    static assert(!__traits(compiles, s.withZeroDigit(null)));
}

// decimal_style.tsv text: printable ASCII but `\` as it is, any other UTF-16 unit as `\uXXXX`.
private string escapedUtf16(scope const(char)[] text) pure
{
    import flint.engine.aot.text : decodeUtf8;

    static immutable hex = "0123456789ABCDEF";
    string result;
    void unit(uint u)
    {
        if (u >= 0x20 && u < 0x7F && u != '\\')
            result ~= cast(char) u;
        else
            result ~= ['\\', 'u', hex[u >> 12], hex[(u >> 8) & 15], hex[(u >> 4) & 15], hex[u & 15]];
    }

    size_t i;
    while (i < text.length)
    {
        const c = decodeUtf8(text, i);
        if (c > 0xFFFF)
        {
            unit(0xD800 + ((c - 0x10000) >> 10));
            unit(0xDC00 + ((c - 0x10000) & 0x3FF));
        }
        else
            unit(c);
    }
    return result;
}

// The UTF-8 text of decimal_style.tsv's escaped input, which has no surrogate.
private string unescapedUtf16(string text) pure
{
    import flint.engine.aot.text : utf8;
    import std.conv : to;

    string result;
    for (size_t i = 0; i < text.length; ++i)
    {
        if (text[i] != '\\')
        {
            result ~= text[i];
            continue;
        }
        uint unit = text[i + 2 .. i + 6].to!uint(16);
        i += 5;
        // A surrogate pair is one character.
        if (unit >= 0xD800 && unit < 0xDC00 && i + 6 < text.length && text[i + 1] == '\\')
        {
            const low = text[i + 3 .. i + 7].to!uint(16);
            if (low >= 0xDC00 && low < 0xE000)
            {
                unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
                i += 6;
            }
        }
        result ~= utf8(cast(dchar) unit);
    }
    return result;
}

// The formatter a decimal_style.tsv row names, with the named style ("-" leaves the formatter's own).
private DateTimeFormatter decimalStyleFormatter(string styleName, string formatterName)
{
    import flint.java.time.format : DecimalStyle, ResolverStyle;

    const s = DecimalStyle.STANDARD;
    const DecimalStyle[string] styles = [
        "STANDARD": s, "ARABIC": s.withZeroDigit('\u0660'),
        "DEVANAGARI": s.withZeroDigit('\u0966').withPositiveSign('P').withNegativeSign('N')
            .withDecimalSeparator('\u066B'), "MINUS": s.withNegativeSign('\u2212'),
        "COMMA": s.withDecimalSeparator(','),
        "LETTERS": s.withZeroDigit('A').withPositiveSign('p').withNegativeSign('n')
            .withDecimalSeparator('d'), "WRAP": s.withZeroDigit('\uFFF8'),
        "SURROGATE": s.withZeroDigit('\uD7FB'), "SAMESIGN": s.withPositiveSign('-'),
        "DIGITSIGN": s.withPositiveSign('1').withNegativeSign('2'),
        "NUL": s.withZeroDigit('\0').withDecimalSeparator('\0'),
        "FULLWIDTH": s.withNegativeSign('\uFF0D').withPositiveSign('\uFF0B').withDecimalSeparator('\u3002'),
    ];
    const DateTimeFormatter[string] constants = [
        "ISO_LOCAL_DATE": DateTimeFormatter.ISO_LOCAL_DATE,
        "ISO_LOCAL_TIME": DateTimeFormatter.ISO_LOCAL_TIME,
        "ISO_LOCAL_DATE_TIME": DateTimeFormatter.ISO_LOCAL_DATE_TIME,
        "ISO_OFFSET_DATE_TIME": DateTimeFormatter.ISO_OFFSET_DATE_TIME,
        "ISO_INSTANT": DateTimeFormatter.ISO_INSTANT.withZone(ZoneOffset.UTC.toZoneId()),
        "BASIC_ISO_DATE": DateTimeFormatter.BASIC_ISO_DATE,
        "ISO_ORDINAL_DATE": DateTimeFormatter.ISO_ORDINAL_DATE,
        "ISO_WEEK_DATE": DateTimeFormatter.ISO_WEEK_DATE, "ISO_DATE": DateTimeFormatter.ISO_DATE,
        "ISO_TIME": DateTimeFormatter.ISO_TIME,
        "RFC_1123_DATE_TIME": DateTimeFormatter.RFC_1123_DATE_TIME,
        "ISO_LOCAL_DATE.withZone": DateTimeFormatter.ISO_LOCAL_DATE,
        "ISO_LOCAL_DATE.withResolverStyle": DateTimeFormatter.ISO_LOCAL_DATE,
    ];
    auto base = formatterName in constants;
    DateTimeFormatter f = base ? *base : DateTimeFormatter.ofPattern(formatterName);
    if (styleName != "-")
        f = f.withDecimalStyle(styles[styleName]);
    if (formatterName == "ISO_LOCAL_DATE.withZone")
        f = f.withZone(ZoneOffset.UTC.toZoneId());
    else if (formatterName == "ISO_LOCAL_DATE.withResolverStyle")
        f = f.withResolverStyle(ResolverStyle.SMART);
    return f;
}

// Formats the value of `kind` whose toString is `text`.
private string decimalStyleFormat(string kind, const DateTimeFormatter f, string text)
{
    switch (kind)
    {
    case "date":
        return f.format(LocalDate.parse(text));
    case "time":
        return f.format(LocalTime.parse(text));
    case "dateTime":
        return f.format(LocalDateTime.parse(text));
    case "offset":
        return f.format(OffsetDateTime.parse(text));
    default:
        return f.format(Instant.parse(text));
    }
}

// Parses `text` into a value of `kind`; returns its toString.
private string decimalStyleParse(string kind, const DateTimeFormatter f, string text)
{
    switch (kind)
    {
    case "date":
        return LocalDate.parse(text, f).toString();
    case "time":
        return LocalTime.parse(text, f).toString();
    case "dateTime":
        return LocalDateTime.parse(text, f).toString();
    case "offset":
        return OffsetDateTime.parse(text, f).toString();
    default:
        return ZonedDateTime.parse(text, f).toString();
    }
}

// One operation of decimal_style.tsv: the escaped result's toString, or `!` and the exception message (and a parse
// exception's error index).
private string decimalStyleResult(string op, string styleName, string formatterName, string input)
{
    import flint.engine.aot.text : decimal;

    static immutable string[string] kinds = [
        "ISO_LOCAL_DATE": "date", "ISO_LOCAL_TIME": "time", "ISO_LOCAL_DATE_TIME": "dateTime",
        "ISO_OFFSET_DATE_TIME": "offset", "ISO_INSTANT": "instant", "BASIC_ISO_DATE": "date",
        "ISO_ORDINAL_DATE": "date", "ISO_WEEK_DATE": "date", "ISO_DATE": "date", "ISO_TIME": "time",
        "RFC_1123_DATE_TIME": "offset", "uuuu-MM-dd": "date", "u-M-d": "date", "yy-MM-dd": "date",
        "yyyy-MM-dd": "date", "uuuuMMdd": "date", "uuuu D": "date", "HH:mm:ss.SSS": "time",
        "H:m:s n": "time", "hh:mm a": "time", "uuuu-MM-dd'T'HH:mm:ssXXX": "offset",
        "uuuu-MM-dd HH:mm:ss.SSSSSSSSS xx": "offset", "EEE, d MMM uuuu": "date",
    ];
    const f = decimalStyleFormatter(styleName, formatterName);
    if (op == "getDecimalStyle")
        return escapedUtf16(f.getDecimalStyle().toString());
    if (op == "toString")
        return escapedUtf16(f.toString());
    const kind = kinds[formatterName], text = unescapedUtf16(input);
    try
        return escapedUtf16(op == "format" ? decimalStyleFormat(kind, f, text) : decimalStyleParse(kind, f, text));
    catch (DateTimeParseException e)
        return "!" ~ escapedUtf16(e.msg) ~ "\t" ~ decimal(e.getErrorIndex());
    catch (DateTimeException e)
        return "!" ~ escapedUtf16(e.msg);
}

@("DateTimeFormatter.withDecimalStyle prints and parses localized digits, signs and separators like JDK 21")
unittest
{
    import std.array : join;

    size_t count, failures;
    string report;
    foreach (row; rows(import("decimal_style.tsv")))
    {
        const expected = row[4 .. $].join("\t");
        const got = decimalStyleResult(row[0], row[1], row[2], row[3]);
        if (got != expected)
        {
            if (++failures <= 40)
                report ~= row[0 .. 4].join(" | ") ~ ": " ~ got ~ " != " ~ expected ~ "\n";
        }
        ++count;
    }
    assert(failures == 0, report);
    assert(count == 4396);
}

// The formatter a formatter_builder.tsv recipe makes; see GoldenFormatterBuilder.java for its steps.
private DateTimeFormatter builderRecipe(string recipe)
{
    import std.array : split;

    static DateTimeFormatter named(string name)
    {
        const DateTimeFormatter[string] constants = [
            "ISO_LOCAL_DATE": DateTimeFormatter.ISO_LOCAL_DATE,
            "ISO_LOCAL_TIME": DateTimeFormatter.ISO_LOCAL_TIME,
            "ISO_LOCAL_DATE_TIME": DateTimeFormatter.ISO_LOCAL_DATE_TIME,
            "ISO_OFFSET_DATE_TIME": DateTimeFormatter.ISO_OFFSET_DATE_TIME,
            "ISO_OFFSET_DATE": DateTimeFormatter.ISO_OFFSET_DATE,
            "ISO_DATE": DateTimeFormatter.ISO_DATE, "ISO_DATE_TIME": DateTimeFormatter.ISO_DATE_TIME,
            "ISO_TIME": DateTimeFormatter.ISO_TIME, "ISO_INSTANT": DateTimeFormatter.ISO_INSTANT,
            "BASIC_ISO_DATE": DateTimeFormatter.BASIC_ISO_DATE,
            "ISO_ORDINAL_DATE": DateTimeFormatter.ISO_ORDINAL_DATE,
        ];
        return name[0] == '=' ? DateTimeFormatter.ofPattern(name[1 .. $]) : constants[name];
    }

    DateTimeFormatterBuilder b;
    foreach (step; recipe.length ? recipe.split("|") : null)
    {
        if (step.length >= 2 && step[1] == ':')
            builderStep(b, step[0], step[2 .. $], &named);
        else
            builderSetting(b, step);
    }
    return b.toFormatter();
}

// A recipe step without an argument.
private void builderSetting(ref DateTimeFormatterBuilder b, string step)
{
    switch (step)
    {
    case "cs":
        b.parseCaseSensitive();
        break;
    case "ci":
        b.parseCaseInsensitive();
        break;
    case "strict":
        b.parseStrict();
        break;
    case "lenient":
        b.parseLenient();
        break;
    case "inst":
        b.appendInstant();
        break;
    case "offid":
        b.appendOffsetId();
        break;
    case "zid":
        b.appendZoneId();
        break;
    case "zrid":
        b.appendZoneRegionId();
        break;
    case "zo":
        b.appendZoneOrOffsetId();
        break;
    case "[":
        b.optionalStart();
        break;
    default:
        b.optionalEnd();
        break;
    }
}

// A recipe step with an argument; `named` gives the formatter an `a:` or `q:` step names.
private void builderStep(ref DateTimeFormatterBuilder b, char step, string arg,
        DateTimeFormatter function(string) @safe named)
{
    import flint.engine.aot.text : decodeUtf8;
    import std.algorithm.searching : findSplit;
    import std.conv : to;

    switch (step)
    {
    case 'c':
        size_t next;
        b.appendLiteral(cast(wchar) decodeUtf8(arg, next));
        break;
    case 's':
        b.appendLiteral(arg);
        break;
    case 'p':
        b.appendPattern(arg);
        break;
    case 'o':
        auto parts = arg.findSplit(",");
        b.appendOffset(parts[0], parts[2]);
        break;
    case 'l':
        b.appendLocalizedOffset(arg.to!TextStyle);
        break;
    case 'd':
        b.appendDayPeriodText(arg.to!TextStyle);
        break;
    case 'i':
        b.appendInstant(arg.to!int);
        break;
    case 'P':
        auto padParts = arg.findSplit(",");
        if (padParts[1].length)
        {
            size_t offset;
            b.padNext(padParts[0].to!int, cast(wchar) decodeUtf8(padParts[2], offset));
        }
        else
            b.padNext(padParts[0].to!int);
        break;
    case 'a':
        b.append(named(arg));
        break;
    default:
        b.appendOptional(named(arg));
        break;
    }
}

// One operation of formatter_builder.tsv: the escaped result, or `!` and the exception message (and a parse
// exception's error index).
private string builderResult(string op, string recipe, string kind, string input)
{
    import flint.engine.aot.text : decimal;
    import flint.java.lang : IllegalStateException;

    try
    {
        const f = builderRecipe(unescapedUtf16(recipe));
        if (op == "build")
            return escapedUtf16(f.toString());
        const text = unescapedUtf16(input);
        if (op == "parse")
            return escapedUtf16(decimalStyleParse(kind, f, text));
        switch (kind)
        {
        case "zoned":
            return escapedUtf16(f.format(ZonedDateTime.parse(text)));
        case "instant":
            return escapedUtf16(f.format(Instant.parse(text)));
        default:
            return escapedUtf16(decimalStyleFormat(kind, f, text));
        }
    }
    catch (DateTimeParseException e)
        return "!" ~ escapedUtf16(e.msg) ~ "\t" ~ decimal(e.getErrorIndex());
    catch (DateTimeException e)
        return "!" ~ escapedUtf16(e.msg);
    catch (IllegalArgumentException e)
        return "!" ~ escapedUtf16(e.msg);
    catch (IllegalStateException e)
        return "!" ~ escapedUtf16(e.msg);
}

// `result` with its Parsed field list written as `{?}`, as GoldenFormatterBuilder.java writes Java's when the list
// order is HashMap order.
private string unorderedParsed(string result) pure
{
    import std.string : indexOf;

    enum marker = "TemporalAccessor: {";
    const start = result.indexOf(marker);
    if (start < 0)
        return result;
    const close = result.indexOf('}', start);
    return result[0 .. start + marker.length] ~ "?" ~ result[close .. $];
}

@("DateTimeFormatterBuilder describes, prints and parses like JDK 21")
unittest
{
    import std.algorithm.searching : canFind;
    import std.array : join;

    size_t count, failures;
    string report;
    foreach (row; rows(import("formatter_builder.tsv")))
    {
        const expected = row[4 .. $].join("\t");
        auto got = builderResult(row[0], row[1], row[2], row.length > 3 ? row[3] : "");
        if (expected.canFind("TemporalAccessor: {?}"))
            got = unorderedParsed(got);
        if (got != expected)
        {
            if (++failures <= 60)
                report ~= row[0 .. 4].join(" | ") ~ ": " ~ got ~ " != " ~ expected ~ "\n";
        }
        ++count;
    }
    assert(failures == 0, report);
    assert(count == 6131);
}

@("appendInstant(int) parses exactly its fractional digits, or up to nine for -1")
unittest
{
    import std.exception : collectException;

    // Java resolves only the instant; Flint resolves the parsed local date-time and offset, which give the same
    // instant here (the golden file leaves out these rows, see GoldenFormatterBuilder.java).
    static string parsed(int digits, string text)
    {
        auto b = DateTimeFormatterBuilder();
        return OffsetDateTime.parse(text, b.appendInstant(digits).toFormatter()).toString();
    }

    assert(parsed(3, "2024-03-05T10:15:30.120Z") == "2024-03-05T10:15:30.120Z");
    assert(parsed(1, "2024-03-05T10:15:30.5+01:00") == "2024-03-05T10:15:30.500+01:00");
    assert(parsed(9, "2024-03-05T10:15:30.000000001Z") == "2024-03-05T10:15:30.000000001Z");
    assert(parsed(-1, "2024-03-05T10:15:30Z") == "2024-03-05T10:15:30Z");
    assert(parsed(-1, "2024-03-05T10:15:30.12345Z") == "2024-03-05T10:15:30.123450Z");
    auto e = collectException!DateTimeParseException(parsed(3, "2024-03-05T10:15:30.12Z"));
    assert(e !is null && e.getErrorIndex() == 20);
}

@("padNext pads the next appended element and parses within the pad width")
unittest
{
    import std.exception : collectException;

    auto padded = DateTimeFormatterBuilder().padNext(5).appendPattern("HH:mm").toFormatter();
    assert(padded.toString() == "Pad(Value(HourOfDay,2),5)':'Value(MinuteOfHour,2)");
    assert(padded.format(LocalTime.of(10, 15)) == "   10:15");
    assert(LocalTime.parse("   10:15", padded) == LocalTime.of(10, 15));
    // A strict parse needs the whole pad width, and a wrapped element that fails inside it still fails at the pad
    // start plus the start again, as Java's decorator reports.
    auto tooShort = collectException!DateTimeParseException(padded.parse("10"));
    assert(tooShort !is null && tooShort.getErrorIndex() == 0);
    auto shortText = collectException!DateTimeParseException(padded.parse(" 10:15"));
    assert(shortText !is null && shortText.getErrorIndex() == 1);
    // The pad character, and a lenient parse treating the width as a maximum.
    auto starred = DateTimeFormatterBuilder().padNext(5, '*').appendPattern("HH").toFormatter();
    assert(starred.toString() == "Pad(Value(HourOfDay,2),5,'*')");
    assert(starred.format(LocalTime.of(10, 15)) == "***10");
    assert(LocalTime.parse("***10", starred) == LocalTime.of(10, 0));
    auto lenient = DateTimeFormatterBuilder().parseLenient().padNext(5).appendPattern("HH").toFormatter();
    assert(LocalTime.parse("10", lenient) == LocalTime.of(10, 0));
    // Printing past the pad width fails, and a width below one is rejected.
    assert(collectException!DateTimeException(DateTimeFormatterBuilder().padNext(1)
            .appendPattern("HH").toFormatter().format(LocalTime.of(10, 0))).msg
            == "Cannot print as output of 2 characters exceeds pad width of 1");
    assert(collectException!IllegalArgumentException(DateTimeFormatterBuilder().padNext(0))
            .msg == "The pad width must be at least one but was 0");
}

@("DateTimeFormatterBuilder prints and parses the single-digit hour offset patterns")
unittest
{
    import std.exception : collectException;

    // A single-digit hour prints one digit below ten and two from ten; the description keeps the pattern.
    auto single = DateTimeFormatterBuilder().appendPattern("uuuu-MM-dd'T'HH:mm")
        .appendOffset("+H:mm", "Z").toFormatter();
    assert(single.toString() == "Value(Year,4,19,EXCEEDS_PAD)'-'Value(MonthOfYear,2)'-'Value(DayOfMonth,2)'T'"
            ~ "Value(HourOfDay,2)':'Value(MinuteOfHour,2)Offset(+H:mm,'Z')");
    static string printed(DateTimeFormatter formatter, int hours, int minutes)
    {
        return formatter.format(OffsetDateTime.of(2024, 3, 5, 10, 15, 0, 0, ZoneOffset.ofHoursMinutes(hours, minutes)));
    }

    assert(printed(single, 1, 30) == "2024-03-05T10:15+1:30");
    assert(printed(single, 10, 0) == "2024-03-05T10:15+10");
    assert(printed(single, 18, 0) == "2024-03-05T10:15+18");
    assert(printed(single, 0, 0) == "2024-03-05T10:15Z");
    // Java's variable-width forms read a run of digits: +Hmm takes one to four, +HMM three or four.
    auto wide = DateTimeFormatterBuilder().appendPattern("uuuu-MM-dd'T'HH:mm").appendOffset("+Hmm", "Z").toFormatter();
    assert(OffsetDateTime.parse("2024-03-05T10:15+1", wide).toString() == "2024-03-05T10:15+01:00");
    assert(OffsetDateTime.parse("2024-03-05T10:15+130", wide).toString() == "2024-03-05T10:15+01:30");
    auto mandatory = DateTimeFormatterBuilder().appendPattern("uuuu-MM-dd'T'HH:mm")
        .appendOffset("+HMM", "Z").toFormatter();
    assert(OffsetDateTime.parse("2024-03-05T10:15+130", mandatory).toString() == "2024-03-05T10:15+01:30");
    // A lenient "+H" reads colon-separated groups when the text shows a colon.
    auto lenient = DateTimeFormatterBuilder().appendPattern("uuuu-MM-dd'T'HH:mm").parseLenient()
        .appendOffset("+H", "Z").toFormatter();
    assert(OffsetDateTime.parse("2024-03-05T10:15+1:30", lenient).toString() == "2024-03-05T10:15+01:30");
    assert(OffsetDateTime.parse("2024-03-05T10:15+130", lenient).toString() == "2024-03-05T10:15+01:30");
    // An undefined pattern still throws Java's message.
    assert(collectException!IllegalArgumentException(DateTimeFormatterBuilder().appendOffset("+X",
            "Z")).msg == "Invalid zone offset pattern: +X");
    // A case-insensitive parse folds ASCII letters only; Java folds "É" to "é" too.
    auto literal = DateTimeFormatterBuilder().parseCaseInsensitive().appendLiteral("été").toFormatter();
    try
    {
        literal.parse("ÉTÉ");
        assert(false);
    }
    catch (DateTimeParseException e)
        assert(e.getErrorIndex() == 0);
    literal.parse("éTé");
    // Java's message for a value without a region names the zone query's lambda.
    try
    {
        DateTimeFormatterBuilder().appendZoneRegionId().toFormatter().format(LocalDate.of(2024, 1, 1));
        assert(false);
    }
    catch (DateTimeException e)
        assert(e.msg == "Unsupported field: ZoneId", e.msg);
    // A lone surrogate literal prints as U+FFFD (R14); the chain reads as Java's.
    auto f = DateTimeFormatterBuilder().appendLiteral(cast(wchar) 0xD800).appendPattern("uuuu").toFormatter();
    assert(f.format(LocalDate.of(2024, 1, 1)) == "�2024");
    assert(DateTimeFormatterBuilder().appendPattern("uuuu").appendLiteral('-').toFormatter()
            .format(LocalDate.of(2024, 1, 1)) == "2024-");
}

@("java.time: Instant and Duration arithmetic overflows as Java's does")
unittest
{
    import std.exception : collectException;

    enum long maxSecond = 31_556_889_864_403_199L, minSecond = -31_557_014_167_219_200L;
    enum rangeMessage = "Instant exceeds minimum or maximum instant", overflow = "long overflow";
    enum capacity = "Exceeds capacity of Duration: 9223372036854775808000000000";
    // Instants stay within -1000000000-01-01T00:00Z .. 1000000000-12-31T23:59:59.999999999Z.
    assert(Instant.ofEpochSecond(maxSecond, 999_999_999).toString() == "+1000000000-12-31T23:59:59.999999999Z");
    assert(collectException!DateTimeException(Instant.ofEpochSecond(maxSecond + 1)).msg == rangeMessage);
    assert(collectException!DateTimeException(Instant.ofEpochSecond(minSecond, -1)).msg == rangeMessage);
    assert(collectException!ArithmeticException(Instant.ofEpochSecond(long.max, 1_000_000_000)).msg == overflow);
    const max = Instant.ofEpochSecond(maxSecond, 999_999_999);
    assert(collectException!DateTimeException(max.plusNanos(1)).msg == rangeMessage);
    assert(collectException!ArithmeticException(max.plusSeconds(long.max)).msg == overflow);
    assert(collectException!ArithmeticException(max.minusSeconds(long.min)).msg == overflow);
    // Java adds a duration's seconds before its nanoseconds, so the first step can leave the range.
    const nearMin = Instant.ofEpochSecond(minSecond, 5);
    assert(collectException!DateTimeException(nearMin.plus(Duration.ofNanos(-1))).msg == rangeMessage);
    assert(nearMin.plusNanos(-1).getNano() == 4);
    // Milliseconds count from the next second up for a negative instant with a fraction.
    assert(Instant.ofEpochSecond(-9_223_372_036_854_776L, 192_000_000).toEpochMilli() == long.min);
    assert(collectException!ArithmeticException(Instant.ofEpochSecond(-9_223_372_036_854_776L,
            191_999_999).toEpochMilli()).msg == overflow);

    assert(collectException!ArithmeticException(Duration.ofDays(106_751_991_167_301L)).msg == overflow);
    assert(collectException!ArithmeticException(Duration.ofSeconds(long.min, -1)).msg == overflow);
    assert(collectException!ArithmeticException(Duration.ofSeconds(long.max).plusMillis(1_000)).msg == overflow);
    assert(Duration.ofSeconds(long.min).minus(Duration.ofSeconds(long.min)).isZero());
    assert(collectException!ArithmeticException(Duration.ofSeconds(long.min).negated()).msg == capacity);
    assert(Duration.ofSeconds(long.min, 1).abs().toString() == "PT2562047788015215H30M7.999999999S");
    // Duration.parse reports the overflow as Java does.
    auto failure = collectException!DateTimeParseException(Duration.parse("-PT-9223372036854775808S"));
    assert(failure.msg == "Text cannot be parsed to a Duration: overflow", failure.msg);
    assert(failure.getCause().msg == capacity);
    assert(collectException!DateTimeParseException(Duration.parse("PT-9223372036854775808.5S"))
            .getCause().msg == overflow);
}
