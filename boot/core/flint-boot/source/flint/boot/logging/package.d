// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/logging/LogLevel.java
// with LoggingSystemProperty.java, and the console pattern of
// core/spring-boot/src/main/resources/org/springframework/boot/logging/logback/defaults.xml together with
// logback/ColorConverter.java and logback/EnclosedInSquareBracketsConverter.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the pattern is rendered by a fixed D formatter instead of Logback's pattern layout;
// Logback's own converters (padding, truncation, logger-name abbreviation) are reimplemented from Logback's
// documented behaviour, not ported (Logback is EPL-2.0/LGPL).

/// `org.springframework.boot.logging`: log levels and Boot's default console format.
///
/// Boot's default console line, from `CONSOLE_LOG_PATTERN`:
///
/// ```
/// 2026-11-23T10:15:30.123+01:00  INFO 12345 --- [demo] [           main] c.e.restservice.RestServiceApplication   : Started
/// ```
///
/// Its fields are:
/// - the ISO-8601 timestamp with millisecond precision and offset (`yyyy-MM-dd'T'HH:mm:ss.SSSXXX`);
/// - the level, right-aligned in five columns (`%5p`);
/// - the PID;
/// - `---`;
/// - `[flint.application.name]` and `[flint.application.group]` when they are set;
/// - the thread name, right-aligned in fifteen columns and truncated from the left (`%15.15t`);
/// - the logger name, abbreviated to 39 characters, left-aligned in forty columns and truncated from the left
///   (`%-40.40logger{39}`);
/// - ` : ` and the message;
/// - a following stack trace when there is a throwable.
///
/// With ANSI output enabled, the parts are coloured as `%clr` does: faint, a level colour, magenta and cyan.
module flint.boot.logging;

@safe:

/// Logging levels supported by a logging system.
enum LogLevel
{
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR,
    FATAL,
    OFF
}

/// One log event, as a logging system hands it to the console format.
struct LogEvent
{
    /// Milliseconds since the Unix epoch.
    long timestampMillis;
    /// The offset from UTC, in minutes, of the zone the timestamp prints in.
    int utcOffsetMinutes;
    /// The level.
    LogLevel level;
    /// The process id.
    long pid;
    /// The thread (or fiber) name.
    string thread = "main";
    /// The logger's name, usually a fully qualified type name.
    string logger;
    /// The formatted message.
    string message;
    /// The throwable's rendering (`Type: message` and frames), or `null`.
    string throwable;
}

/// Boot's console line format with its `LoggingSystemProperty` inputs.
struct ConsoleLogFormat
{
    /// `flint.application.name` (`APPLICATION_NAME`), shown in brackets when set.
    string applicationName;
    /// `flint.application.group` (`APPLICATION_GROUP`), shown in brackets when set.
    string applicationGroup;
    /// `flint.output.ansi.enabled`: whether to colour the output.
    bool ansi;
    /// `logging.pattern.correlation` (`LOG_CORRELATION_PATTERN`), already rendered for the event; usually empty.
    string correlation;

    /// The console line(s) for `event`, ending with a newline.
    string format(const LogEvent event) const
    {
        string line = color(timestamp(event.timestampMillis, event.utcOffsetMinutes), Ansi.faint) ~ " ";
        line ~= color(padLeft(levelName(event.level), 5), levelColor(event.level)) ~ " ";
        line ~= color(pidText(event.pid), Ansi.magenta) ~ " ";
        line ~= color("--- " ~ enclosed(applicationName) ~ enclosed(applicationGroup) ~ "[" ~ fit(event.thread,
                15, true) ~ "] " ~ correlation, Ansi.faint);
        line ~= color(fit(abbreviate(event.logger, 39), 40, false), Ansi.cyan) ~ " ";
        line ~= color(":", Ansi.faint) ~ " " ~ event.message ~ "\n";
        if (event.throwable.length)
            line ~= event.throwable ~ (event.throwable[$ - 1] == '\n' ? "" : "\n");
        return line;
    }

    private string color(string text, string code) const pure
    {
        return ansi && code.length ? "\x1b[" ~ code ~ "m" ~ text ~ "\x1b[0;39m" : text;
    }
}

/// ANSI SGR codes `%clr` uses.
private struct Ansi
{
    enum faint = "2";
    enum red = "31";
    enum green = "32";
    enum yellow = "33";
    enum magenta = "35";
    enum cyan = "36";
}

private string levelColor(LogLevel level) pure nothrow @nogc
{
    switch (level)
    {
    case LogLevel.FATAL:
    case LogLevel.ERROR:
        return Ansi.red;
    case LogLevel.WARN:
        return Ansi.yellow;
    default:
        return Ansi.green;
    }
}

/// Logback's level names, as `%p` prints them; Boot maps FATAL to ERROR for Logback.
string levelName(LogLevel level) pure nothrow @nogc
{
    final switch (level)
    {
    case LogLevel.TRACE:
        return "TRACE";
    case LogLevel.DEBUG:
        return "DEBUG";
    case LogLevel.INFO:
        return "INFO";
    case LogLevel.WARN:
        return "WARN";
    case LogLevel.ERROR:
    case LogLevel.FATAL:
        return "ERROR";
    case LogLevel.OFF:
        return "OFF";
    }
}

private string pidText(long pid) pure
{
    import std.conv : to;

    return pid > 0 ? pid.to!string : "";
}

/// `EnclosedInSquareBracketsConverter`: `[value] ` when set, else nothing.
string enclosed(string value) pure
{
    return value.length ? "[" ~ value ~ "] " : "";
}

/// `yyyy-MM-dd'T'HH:mm:ss.SSSXXX` for a timestamp in the zone `offsetMinutes` from UTC.
string timestamp(long millis, int offsetMinutes) pure nothrow
{
    const local = millis + offsetMinutes * 60_000L;
    const days = floorDiv(local, 86_400_000L);
    const ms = local - days * 86_400_000L;
    const date = civilFromDays(days);
    const day = padded(date.year, 4) ~ "-" ~ padded(date.month, 2) ~ "-" ~ padded(date.day, 2);
    const time = padded(ms / 3_600_000, 2) ~ ":" ~ padded(ms / 60_000 % 60, 2) ~ ":" ~ padded(ms / 1000 % 60, 2);
    const text = day ~ "T" ~ time ~ "." ~ padded(ms % 1000, 3);
    if (offsetMinutes == 0)
        return text ~ "Z";
    const sign = offsetMinutes < 0 ? "-" : "+";
    const magnitude = offsetMinutes < 0 ? -offsetMinutes : offsetMinutes;
    return text ~ sign ~ padded(magnitude / 60, 2) ~ ":" ~ padded(magnitude % 60, 2);
}

/// `%0<width>d`: at least `width` digits, zero-filled, with a leading `-` for a negative value (counted in the width,
/// as std.format counts it).
private string padded(long value, size_t width) pure nothrow
{
    char[24] digits;
    size_t at = digits.length;
    ulong magnitude = value < 0 ? 0 - cast(ulong) value : cast(ulong) value;
    do
    {
        digits[--at] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude);
    const signed = value < 0 ? 1 : 0;
    while (digits.length - at + signed < width && at > signed)
        digits[--at] = '0';
    if (signed)
        digits[--at] = '-';
    return digits[at .. $].idup;
}

unittest
{
    assert(padded(7, 2) == "07" && padded(2026, 4) == "2026" && padded(12_345, 4) == "12345");
    assert(padded(-5, 4) == "-005" && padded(0, 3) == "000");
    assert(timestamp(0, 0) == "1970-01-01T00:00:00.000Z");
    assert(timestamp(1_764_057_600_123, -300) == "2025-11-25T03:00:00.123-05:00");
    assert(timestamp(1_764_057_600_123, 330) == "2025-11-25T13:30:00.123+05:30");
    assert(timestamp(-1, 0) == "1969-12-31T23:59:59.999Z");
}

private long floorDiv(long a, long b) pure nothrow @nogc
{
    const q = a / b;
    return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q;
}

// Howard Hinnant's days-to-civil conversion (proleptic Gregorian).
private struct CivilDate
{
    int year;
    int month;
    int day;
}

private CivilDate civilFromDays(long z) pure nothrow @nogc
{
    z += 719_468;
    const era = (z >= 0 ? z : z - 146_096) / 146_097;
    const doe = z - era * 146_097;
    const yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    const day = cast(int)(doy - (153 * mp + 2) / 5 + 1);
    const month = cast(int)(mp < 10 ? mp + 3 : mp - 9);
    return CivilDate(cast(int)(yoe + era * 400 + (month <= 2 ? 1 : 0)), month, day);
}

/// Pad `text` on the left to `width`.
string padLeft(string text, size_t width) pure
{
    return text.length >= width ? text : spaces(width - text.length) ~ text;
}

/// Logback's `%N.Mx` with N == M: pad to `width` (right-aligned when `alignRight`, as `%15`, left-aligned as
/// `%-40`), and truncate a longer value from the left, keeping its end.
string fit(string text, size_t width, bool alignRight) pure
{
    if (text.length > width)
        return text[text.length - width .. text.length];
    if (alignRight)
        return padLeft(text, width);
    return text ~ spaces(width - text.length);
}

private string spaces(size_t count) pure
{
    auto result = new char[count];
    result[] = ' ';
    return result.idup;
}

/// Logback's target-length logger-name abbreviation (`%logger{39}`): when the name is longer than `target`,
/// package segments are shortened to their first character, leftmost first, until it fits; the last segment is
/// never shortened.
string abbreviate(string name, size_t target) pure
{
    import std.array : join, split;

    if (name.length <= target)
        return name;
    auto parts = name.split('.');
    if (parts.length == 1)
        return name;
    size_t length = name.length;
    foreach (index; 0 .. parts.length)
    {
        if (length <= target || index + 1 == parts.length)
            break;
        if (parts[index].length > 1)
        {
            length = length + 1 - parts[index].length;
            parts[index] = parts[index][0 .. 1];
        }
    }
    return parts.join(".");
}
