module flint.java.time_test;

import core.memory : GC;
import flint.java.lang : ArithmeticException, IllegalArgumentException;
import flint.java.time : DateTimeException, DayOfWeek, Duration, Instant, LocalDate, LocalDateTime,
    LocalTime, Month, OffsetDateTime, ZoneId, ZoneOffset, ZonedDateTime, getValue, isLeap;
import flint.java.time.format : DateTimeFormatter, DateTimeParseException;

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
    assert(odt.atZoneSameInstant(ZoneId.of("UTC")).toString() == "2010-09-07T08:15Z[UTC]");
    assert(odt.isBefore(LocalDateTime.of(2010, 9, 7, 9, 15).atOffset(ZoneOffset.UTC)));
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
    try
    {
        DateTimeFormatter.ofPattern("G yyyy");
        assert(false);
    }
    catch (IllegalArgumentException e)
        assert(e.msg == "Pattern letter not supported by Flint yet: G");
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
