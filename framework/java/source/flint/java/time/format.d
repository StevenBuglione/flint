/++
Java's `java.time.format`: `DateTimeFormatter`, its ISO constants and `ofPattern`, `DateTimeFormatterBuilder`, and
`DateTimeParseException`.

Written from the Java SE 21 API specification of `DateTimeFormatter` and `DateTimeFormatterBuilder`; OpenJDK
21.0.13's `DateTimeFormatterBuilder.java`, `DateTimeParseContext.java` and `SignStyle.java` (GPL-2.0-only WITH
Classpath-exception-2.0) were consulted for the sign, adjacent-width, optional-section and offset parse rules.
Modified by the Flint authors.
A formatter is a list of printer-parser elements, as the specification describes: numeric fields with a width and
sign style, fractions, literals, text, offsets, zone IDs, the instant, and optional sections. English text only;
`Locale` arguments are not supported yet.

`Fields` stands in for `TemporalAccessor`: the erased set of fields one value supplies to a formatter, or one parse
produces.
+/
module flint.java.time.format;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : ArithmeticException, IllegalArgumentException, IllegalStateException;
import flint.java.time : DateTimeException, Duration, Instant, LocalDate, LocalDateTime, LocalTime,
    OffsetDateTime, ZoneId, ZoneOffset, ZonedDateTime, checkRange;
import std.typecons : Nullable;

@safe:

/// An error that occurred while parsing: the text and the index of the error are kept.
class DateTimeParseException : DateTimeException
{
    private string parsedString_;
    private int errorIndex_;

    ///
    this(string message, string parsedData, int errorIndex, Throwable cause = null,
            string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
        parsedString_ = parsedData;
        errorIndex_ = errorIndex;
    }

    /// The text that was being parsed.
    string getParsedString() const pure nothrow @nogc
    {
        return parsedString_;
    }

    /// The index in the text where the error was found, in UTF-16 code units.
    int getErrorIndex() const pure nothrow @nogc
    {
        return errorIndex_;
    }
}

/++
How a parse resolves its fields into dates and times. Java's `LENIENT`, which moves out-of-range values into the next
field, is not supported yet.
+/
enum ResolverStyle
{
    /// Every field must be in range, and a year-of-era without an era is not resolved.
    STRICT,
    /// Day-of-month 29-31 past the month's end moves to its last day, and 24:00 is midnight of the next day.
    SMART,
}

/// Styles of handling signs when printing and parsing numbers.
enum SignStyle
{
    /// A sign for negative values only; a sign is rejected when parsing a positive value strictly.
    NORMAL,
    /// Always a sign.
    ALWAYS,
    /// Never a sign: the absolute value.
    NEVER,
    /// Rejects negative values.
    NOT_NEGATIVE,
    /// A sign for negative values, and '+' when the value exceeds the minimum width.
    EXCEEDS_PAD,
}

/// Styles of a localized date or time formatter, from the most to the least detailed.
enum FormatStyle
{
    /// Full text, the most detail: 'Tuesday, April 12, 1952 AD'.
    FULL,
    /// Long text, with lots of detail: 'January 12, 1952'.
    LONG,
    /// Medium text, with some detail: 'Jan 12, 1952'.
    MEDIUM,
    /// Short text, typically numeric: '12.13.52'.
    SHORT,
}

/++
Sizes of text when printing and parsing. Each size has a normal form, used inside a complete date, and a stand-alone
form; the two alternate, normal first.
+/
enum TextStyle
{
    /// Full text, typically the full description.
    FULL,
    /// Full text for stand-alone use.
    FULL_STANDALONE,
    /// Short text, typically an abbreviation.
    SHORT,
    /// Short text for stand-alone use.
    SHORT_STANDALONE,
    /// Narrow text, typically one letter.
    NARROW,
    /// Narrow text for stand-alone use.
    NARROW_STANDALONE,
}

/// Whether the style is a stand-alone form.
bool isStandalone(TextStyle style) pure nothrow @nogc
{
    final switch (style)
    {
    case TextStyle.FULL, TextStyle.SHORT, TextStyle.NARROW:
        return false;
    case TextStyle.FULL_STANDALONE, TextStyle.SHORT_STANDALONE, TextStyle.NARROW_STANDALONE:
        return true;
    }
}

/// The stand-alone form of the same size.
TextStyle asStandalone(TextStyle style) pure nothrow @nogc
{
    final switch (style)
    {
    case TextStyle.FULL, TextStyle.FULL_STANDALONE:
        return TextStyle.FULL_STANDALONE;
    case TextStyle.SHORT, TextStyle.SHORT_STANDALONE:
        return TextStyle.SHORT_STANDALONE;
    case TextStyle.NARROW, TextStyle.NARROW_STANDALONE:
        return TextStyle.NARROW_STANDALONE;
    }
}

/// The normal form of the same size.
TextStyle asNormal(TextStyle style) pure nothrow @nogc
{
    final switch (style)
    {
    case TextStyle.FULL, TextStyle.FULL_STANDALONE:
        return TextStyle.FULL;
    case TextStyle.SHORT, TextStyle.SHORT_STANDALONE:
        return TextStyle.SHORT;
    case TextStyle.NARROW, TextStyle.NARROW_STANDALONE:
        return TextStyle.NARROW;
    }
}

/++
The localized symbols of numeric text: the zero digit, the positive and negative signs and the decimal separator, each
a UTF-16 code unit as in Java. An immutable value; `DecimalStyle.init` is `STANDARD`. The locale factories `of`,
`ofDefaultLocale` and `getAvailableLocales` are not supported yet.
+/
struct DecimalStyle
{
    /// '0', '+', '-' and '.'.
    static immutable DecimalStyle STANDARD = DecimalStyle.init;

    private wchar zeroDigit_ = '0';
    private wchar positiveSign_ = '+';
    private wchar negativeSign_ = '-';
    private wchar decimalSeparator_ = '.';

    private this(wchar zeroDigit, wchar positiveSign, wchar negativeSign, wchar decimalSeparator) pure nothrow @nogc
    {
        zeroDigit_ = zeroDigit;
        positiveSign_ = positiveSign;
        negativeSign_ = negativeSign;
        decimalSeparator_ = decimalSeparator;
    }

    /// The character that represents zero; the digits one to nine follow it.
    wchar getZeroDigit() const pure nothrow @nogc
    {
        return zeroDigit_;
    }

    /// A copy with a new zero digit.
    DecimalStyle withZeroDigit(wchar zeroDigit) const pure nothrow @nogc
    {
        return DecimalStyle(zeroDigit, positiveSign_, negativeSign_, decimalSeparator_);
    }

    /// The character that represents the positive sign.
    wchar getPositiveSign() const pure nothrow @nogc
    {
        return positiveSign_;
    }

    /// A copy with a new positive sign.
    DecimalStyle withPositiveSign(wchar positiveSign) const pure nothrow @nogc
    {
        return DecimalStyle(zeroDigit_, positiveSign, negativeSign_, decimalSeparator_);
    }

    /// The character that represents the negative sign.
    wchar getNegativeSign() const pure nothrow @nogc
    {
        return negativeSign_;
    }

    /// A copy with a new negative sign.
    DecimalStyle withNegativeSign(wchar negativeSign) const pure nothrow @nogc
    {
        return DecimalStyle(zeroDigit_, positiveSign_, negativeSign, decimalSeparator_);
    }

    /// The character that represents the decimal point.
    wchar getDecimalSeparator() const pure nothrow @nogc
    {
        return decimalSeparator_;
    }

    /// A copy with a new decimal separator.
    DecimalStyle withDecimalSeparator(wchar decimalSeparator) const pure nothrow @nogc
    {
        return DecimalStyle(zeroDigit_, positiveSign_, negativeSign_, decimalSeparator);
    }

    /// Whether all four symbols are equal.
    bool equals(DecimalStyle other) const pure nothrow @nogc
    {
        return this == other;
    }

    /// The sum of the four code units, as Java.
    int hashCode() const pure nothrow @nogc
    {
        return zeroDigit_ + positiveSign_ + negativeSign_ + decimalSeparator_;
    }

    /// `DecimalStyle[0+-.]`. A lone surrogate is written as U+FFFD (R14).
    string toString() const pure nothrow
    {
        import flint.engine.aot.text : utf8;

        const wchar[4] units = [zeroDigit_, positiveSign_, negativeSign_, decimalSeparator_];
        string result = "DecimalStyle[";
        foreach (unit; units)
        {
            const encoded = utf8(unit);
            result ~= encoded is null ? "\uFFFD" : encoded;
        }
        return result ~ "]";
    }
}

private enum Field : ubyte
{
    year,
    yearOfEra,
    monthOfYear,
    dayOfMonth,
    dayOfYear,
    dayOfWeek,
    hourOfDay,
    clockHourOfAmPm,
    minuteOfHour,
    secondOfMinute,
    nanoOfSecond,
    amPmOfDay,
    instantSeconds,
    weekBasedYear, // Java's IsoFields.WEEK_BASED_YEAR
    weekOfWeekBasedYear, // IsoFields.WEEK_OF_WEEK_BASED_YEAR
}

private enum fieldCount = Field.max + 1;

private immutable string[fieldCount] fieldNames = [
    "Year", "YearOfEra", "MonthOfYear", "DayOfMonth", "DayOfYear", "DayOfWeek", "HourOfDay",
    "ClockHourOfAmPm", "MinuteOfHour", "SecondOfMinute", "NanoOfSecond", "AmPmOfDay",
    "InstantSeconds", "WeekBasedYear", "WeekOfWeekBasedYear"
];

/**
 * The fields of a temporal value, as Java's `TemporalAccessor` supplies them to a formatter, or as a parse
 * produces them before they are resolved into a value.
 */
struct Fields
{
    private enum Kind : ubyte
    {
        parsed,
        date,
        time,
        dateTime,
        offsetDateTime,
        zonedDateTime,
        instant,
    }

    private Kind kind_;
    private long[fieldCount] values_;
    private uint present_;
    private bool hasOffset_;
    private int offsetSeconds_;
    private string zoneId_;
    private bool zoneIsRegion_;
    private bool smart_; // ResolverStyle.SMART, as ofPattern and RFC_1123_DATE_TIME resolve; otherwise STRICT

    private void set(Field f, long value) pure nothrow @nogc
    {
        values_[f] = value;
        present_ |= 1u << f;
    }

    private bool has(Field f) const pure nothrow @nogc
    {
        return (present_ & (1u << f)) != 0;
    }

    private void addDate(LocalDate d) pure nothrow @nogc
    {
        set(Field.year, d.getYear());
        set(Field.yearOfEra, d.getYear() >= 1 ? d.getYear() : 1 - cast(long) d.getYear());
        set(Field.monthOfYear, d.getMonthValue());
        set(Field.dayOfMonth, d.getDayOfMonth());
        set(Field.dayOfYear, d.getDayOfYear());
        set(Field.dayOfWeek, d.getDayOfWeek() + 1);
    }

    private void addTime(LocalTime t) pure nothrow @nogc
    {
        set(Field.hourOfDay, t.getHour());
        set(Field.clockHourOfAmPm, t.getHour() % 12 == 0 ? 12 : t.getHour() % 12);
        set(Field.minuteOfHour, t.getMinute());
        set(Field.secondOfMinute, t.getSecond());
        set(Field.nanoOfSecond, t.getNano());
        set(Field.amPmOfDay, t.getHour() / 12);
    }

    private void addOffset(LocalDateTime dateTime, ZoneOffset offset) pure nothrow @nogc
    {
        hasOffset_ = true;
        offsetSeconds_ = offset.getTotalSeconds();
        set(Field.instantSeconds, dateTime.toEpochSecond(offset));
    }

    private void addZone(ZoneId zone) pure nothrow @nogc
    {
        zoneId_ = zone.getId();
        zoneIsRegion_ = !zone.isOffset();
    }

    /// The fields of a date.
    static Fields of(LocalDate value) pure nothrow @nogc
    {
        Fields f;
        f.kind_ = Kind.date;
        f.addDate(value);
        return f;
    }

    /// The fields of a time.
    static Fields of(LocalTime value) pure nothrow @nogc
    {
        Fields f;
        f.kind_ = Kind.time;
        f.addTime(value);
        return f;
    }

    /// The fields of a date-time.
    static Fields of(LocalDateTime value) pure nothrow @nogc
    {
        Fields f;
        f.kind_ = Kind.dateTime;
        f.addDate(value.toLocalDate());
        f.addTime(value.toLocalTime());
        return f;
    }

    /// The fields of a date-time with an offset, the instant included.
    static Fields of(OffsetDateTime value) pure nothrow @nogc
    {
        auto f = of(value.toLocalDateTime());
        f.kind_ = Kind.offsetDateTime;
        f.addOffset(value.toLocalDateTime(), value.getOffset());
        return f;
    }

    /// The fields of a date-time with a zone, the instant and zone ID included.
    static Fields of(ZonedDateTime value) pure nothrow @nogc
    {
        auto f = of(value.toLocalDateTime());
        f.kind_ = Kind.zonedDateTime;
        f.addOffset(value.toLocalDateTime(), value.getOffset());
        f.addZone(value.getZone());
        return f;
    }

    /// The fields of an instant: the instant seconds and the nano-of-second only.
    static Fields of(Instant value) pure nothrow @nogc
    {
        Fields f;
        f.kind_ = Kind.instant;
        f.set(Field.instantSeconds, value.getEpochSecond());
        f.set(Field.nanoOfSecond, value.getNano());
        return f;
    }

    /// The zone ID that was parsed or supplied; empty when none.
    string zoneId() const pure nothrow @nogc
    {
        return zoneId_;
    }

    /// Whether an offset was parsed or supplied.
    bool hasOffset() const pure nothrow @nogc
    {
        return hasOffset_;
    }

    private DateTimeParseException unresolved(scope const(char)[] text, string type) const
    {
        const copy = text.idup;
        return new DateTimeParseException("Text '" ~ copy ~ "' could not be parsed: Unable to obtain "
                ~ type ~ " from TemporalAccessor: " ~ describe() ~ " of type java.time.format.Parsed", copy, 0);
    }

    // The DateTimeParseException for a resolution error: a copy of the text, never the caller's slice.
    private static DateTimeParseException failed(scope const(char)[] text, DateTimeException e)
    {
        const copy = text.idup;
        return new DateTimeParseException("Text '" ~ copy ~ "' could not be parsed: " ~ e.msg, copy, 0, e);
    }

    private bool hasDate() const pure nothrow @nogc
    {
        return (has(Field.year) || (smart_ && has(Field.yearOfEra))) && ((has(Field.monthOfYear)
                && has(Field.dayOfMonth)) || has(Field.dayOfYear));
    }

    private bool hasTime() const pure nothrow @nogc
    {
        return has(Field.hourOfDay) || (has(Field.clockHourOfAmPm) && has(Field.amPmOfDay));
    }

    /// The value these fields came from, as its `toString`; for parsed fields, Java's `Parsed` description.
    string describe() const
    {
        final switch (kind_)
        {
        case Kind.date:
            return toLocalDate("").toString();
        case Kind.time:
            return toLocalTime("").toString();
        case Kind.dateTime:
            return toLocalDate("").toString() ~ "T" ~ toLocalTime("").toString();
        case Kind.offsetDateTime:
            return toLocalDate("").toString() ~ "T" ~ toLocalTime("")
                .toString() ~ toOffset("").toString();
        case Kind.zonedDateTime:
            return describeZoned();
        case Kind.instant:
            return Instant.ofEpochSecond(values_[Field.instantSeconds],
                    values_[Field.nanoOfSecond]).toString();
        case Kind.parsed:
            return describeParsed();
        }
    }

    private string describeZoned() const
    {
        const zoned = toLocalDate("").toString() ~ "T" ~ toLocalTime("").toString() ~ toOffset("").toString();
        return zoneIsRegion_ ? zoned ~ "[" ~ zoneId_ ~ "]" : zoned;
    }

    // Java's `Parsed.toString`: the unresolved fields, the chronology, the zone and what was resolved.
    private string describeParsed() const
    {
        import flint.engine.aot.text : decimal;

        auto text = "{" ~ (hasOffset_ ? "OffsetSeconds=" ~ decimal(offsetSeconds_) : "") ~ "},ISO";
        if (zoneId_.length)
            text ~= "," ~ zoneId_;
        const date = hasDate(), time = hasTime();
        if (date || time)
            text ~= " resolved to ";
        if (date)
            text ~= toLocalDate("").toString() ~ (time ? "T" : "");
        if (time)
            text ~= toLocalTime("").toString();
        return text;
    }

    /// Resolves the date fields into a `LocalDate`; throws `DateTimeParseException` when they are missing or invalid.
    LocalDate toLocalDate(scope const(char)[] text, string type = "LocalDate") const
    {
        const date = resolvedDate(text, type);
        crossCheck(text, date);
        if (!endOfDay())
            return date;
        try
            return date.plusDays(1);
        catch (DateTimeException e)
            throw failed(text, e);
    }

    // The date fields, range-checked; SMART resolution moves an invalid day 29-31 to the end of the month.
    private LocalDate resolvedDate(scope const(char)[] text, string type) const
    {
        long year;
        if (has(Field.year))
            year = values_[Field.year];
        else if (smart_ && has(Field.yearOfEra)) // STRICT does not invent an era
            year = values_[Field.yearOfEra];
        else
            throw unresolved(text, type);
        try
        {
            if (!has(Field.year))
                checkVariable("YearOfEra", year, "999999999/1000000000", 1_000_000_000);
            checkRange("Year", year, -999_999_999, 999_999_999);
            if (has(Field.monthOfYear) && has(Field.dayOfMonth))
            {
                checkRange("MonthOfYear", values_[Field.monthOfYear], 1, 12);
                checkVariable("DayOfMonth", values_[Field.dayOfMonth], "28/31", 31);
                const month = cast(int) values_[Field.monthOfYear];
                int day = cast(int) values_[Field.dayOfMonth];
                if (smart_ && day > 28)
                {
                    const last = LocalDate.of(cast(int) year, month, 1).lengthOfMonth();
                    day = day > last ? last : day;
                }
                return LocalDate.of(cast(int) year, month, day);
            }
            if (has(Field.dayOfYear))
            {
                checkVariable("DayOfYear", values_[Field.dayOfYear], "365/366", 366);
                return LocalDate.ofYearDay(cast(int) year, cast(int) values_[Field.dayOfYear]);
            }
        }
        catch (DateTimeException e)
            throw failed(text, e);
        throw unresolved(text, type);
    }

    // Java's range check of a field whose maximum depends on the month or year, such as `1 - 28/31`.
    private static void checkVariable(string field, long value, string maximums, long largest)
    {
        import flint.engine.aot.text : decimal;

        if (value < 1 || value > largest)
            throw new DateTimeException(
                    "Invalid value for " ~ field ~ " (valid values 1 - " ~ maximums ~ "): " ~ decimal(value));
    }

    // Java's cross-check of a parsed day-of-week against the resolved date.
    private void crossCheck(scope const(char)[] text, LocalDate date) const
    {
        import flint.engine.aot.text : decimal;

        if (!has(Field.dayOfWeek) || date.getDayOfWeek() + 1 == values_[Field.dayOfWeek])
            return;
        const derived = decimal(date.getDayOfWeek() + 1), parsed = decimal(values_[Field.dayOfWeek]);
        throw failed(text, new DateTimeException("Conflict found: Field DayOfWeek " ~ derived
                ~ " differs from DayOfWeek " ~ parsed ~ " derived from " ~ date.toString()));
    }

    // SMART resolution reads 24:00 as midnight at the end of the day.
    private bool endOfDay() const pure nothrow @nogc
    {
        return smart_ && has(Field.hourOfDay) && values_[Field.hourOfDay] == 24
            && value(Field.minuteOfHour) == 0 && value(Field.secondOfMinute) == 0 && value(Field.nanoOfSecond) == 0;
    }

    private long value(Field f) const pure nothrow @nogc
    {
        return has(f) ? values_[f] : 0;
    }

    // Resolves every parsed field, as Java's parse does whatever the queried type: the date, the time, the
    // day-of-week cross-check, then the offset of a date-time.
    private void resolveAll(scope const(char)[] text) const
    {
        const date = hasDate(), time = hasTime();
        LocalDate resolved;
        if (date)
            resolved = resolvedDate(text, "");
        if (time)
            toLocalTime(text);
        if (date)
            crossCheck(text, resolved);
        if (date && time && endOfDay())
            toLocalDate(text);
        if (date && time && hasOffset_)
            toOffset(text);
    }

    /// Resolves the time fields into a `LocalTime`; missing minutes, seconds and nanos are zero.
    LocalTime toLocalTime(scope const(char)[] text, string type = "LocalTime") const
    {
        try
        {
            long hour;
            if (has(Field.hourOfDay))
                hour = values_[Field.hourOfDay];
            else if (has(Field.clockHourOfAmPm) && has(Field.amPmOfDay))
            {
                if (!smart_ || values_[Field.clockHourOfAmPm] != 0) // SMART reads clock hour 0 as 12
                    checkRange("ClockHourOfAmPm", values_[Field.clockHourOfAmPm], 1, 12);
                hour = values_[Field.clockHourOfAmPm] % 12 + 12 * values_[Field.amPmOfDay];
            }
            else
                throw unresolved(text, type);
            if (endOfDay())
                return LocalTime.of(0, 0);
            checkRange("HourOfDay", hour, 0, 23);
            const minute = has(Field.minuteOfHour) ? values_[Field.minuteOfHour] : 0;
            const second = has(Field.secondOfMinute) ? values_[Field.secondOfMinute] : 0;
            const nano = has(Field.nanoOfSecond) ? values_[Field.nanoOfSecond] : 0;
            checkRange("MinuteOfHour", minute, 0, 59);
            checkRange("SecondOfMinute", second, 0, 59);
            return LocalTime.of(cast(int) hour, cast(int) minute, cast(int) second, cast(int) nano);
        }
        catch (DateTimeParseException e)
            throw e;
        catch (DateTimeException e)
            throw failed(text, e);
    }

    // Resolves a parsed week-based year, week and day-of-week into the date, as Java's
    // `IsoFields.WEEK_OF_WEEK_BASED_YEAR` does before the other date fields: the week-based year and the day are
    // range-checked, then the week against the year's 52 or 53 weeks (STRICT) or against 1 - 52/53 (SMART, where
    // week 53 of a 52-week year is the first week of the next).
    private void resolveWeekDate(scope const(char)[] text)
    {
        if (!has(Field.weekBasedYear) || !has(Field.weekOfWeekBasedYear) || !has(Field.dayOfWeek))
            return;
        LocalDate date;
        try
        {
            checkRange("WeekBasedYear", values_[Field.weekBasedYear], -999_999_999, 999_999_999);
            checkRange("DayOfWeek", values_[Field.dayOfWeek], 1, 7);
            const year = cast(int) values_[Field.weekBasedYear];
            const week = values_[Field.weekOfWeekBasedYear], day = values_[Field.dayOfWeek];
            if (!smart_)
                checkRange("WeekOfWeekBasedYear", week, 1, weeksInWeekBasedYear(year));
            else
                checkVariable("WeekOfWeekBasedYear", week, "52/53", 53);
            date = LocalDate.of(year, 1, 4).plusWeeks(week - 1); // 4 January is always in week 1
            date = date.plusDays(day - 1 - date.getDayOfWeek());
        }
        catch (DateTimeException e)
            throw failed(text, e);
        present_ &= ~((1u << Field.weekBasedYear) | (1u << Field.weekOfWeekBasedYear));
        addDate(date);
    }

    // The value a printer prints for `f`: the supplied or parsed value, or a week field derived from the date.
    private bool printedValue(Field f, out long value) const
    {
        if (f >= Field.weekBasedYear)
            return weekValue(f, value);
        if (!has(f))
            return false;
        value = values_[f];
        return true;
    }

    // The ISO week-based year or week of the date these fields hold; false when they hold no date. A week belongs
    // to the year of its Thursday, so the first days of January can be in the previous week-based year and the
    // last days of December in the next.
    private bool weekValue(Field f, out long value) const
    {
        if (!hasDate())
            return false;
        const date = toLocalDate("");
        long year = date.getYear();
        long thursday = date.getDayOfYear() + 3 - date.getDayOfWeek(); // its day-of-year, Monday being 0
        if (thursday < 1)
            thursday += daysInYear(--year);
        else if (thursday > date.lengthOfYear())
            thursday -= daysInYear(year++);
        value = f == Field.weekBasedYear ? year : (thursday - 1) / 7 + 1;
        return true;
    }

    /// The parsed offset; throws `DateTimeParseException` when none was parsed.
    ZoneOffset toOffset(scope const(char)[] text, string type = "ZoneOffset") const
    {
        if (!hasOffset_)
            throw unresolved(text, type);
        try
            return ZoneOffset.ofTotalSeconds(offsetSeconds_);
        catch (DateTimeException e)
            throw failed(text, e);
    }
}

private long daysInYear(long year) pure nothrow @nogc
{
    return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 366 : 365;
}

// 53 weeks when the year starts on a Thursday, or on a Wednesday in a leap year; otherwise 52.
private long weeksInWeekBasedYear(int year)
{
    import flint.java.time : DayOfWeek;

    const first = LocalDate.of(year, 1, 1).getDayOfWeek();
    return first == DayOfWeek.THURSDAY || (first == DayOfWeek.WEDNESDAY && daysInYear(year) == 366) ? 53 : 52;
}

private enum Op : ubyte
{
    number,
    reducedYear,
    fraction,
    literal,
    text,
    offset,
    localizedOffset, // `text` is "full" or "short"
    zoneId,
    zoneRegion,
    zoneOrOffset,
    instant, // `minWidth` is the fractional digits plus 2: 0 for groups of three as needed, 1 for as many as needed
    // Control elements: everything from here on prints nothing.
    optionalStart, // `lenient` set: an appended formatter, which `text` describes
    optionalEnd,
    caseInsensitive,
    caseSensitive,
    lenient,
    strict,
    groupStart, // an appended formatter, which `text` describes
    groupEnd,
    adjacentEnd, // where an empty optional section was: no element, but values before it are not adjacent
    padStart, // `padWidth` and `padChar`: the element or section up to the matching padEnd is padded
    padEnd,
}

private struct Element
{
    Op op;
    Field field;
    ubyte minWidth;
    ubyte maxWidth;
    SignStyle sign;
    string text; // literal text, offset pattern, or "full"/"short" for text
    string noOffsetText;
    bool lenient;
    wchar padChar; // padStart only; these two fill the struct's tail padding
    int padWidth;
}

private Element num(Field f, int min, int max = 0, SignStyle sign = SignStyle.NOT_NEGATIVE) pure nothrow @nogc
{
    return Element(Op.number, f, cast(ubyte) min, cast(ubyte)(max ? max : min), sign);
}

private Element lit(string text) pure nothrow @nogc
{
    Element e;
    e.op = Op.literal;
    e.text = text;
    return e;
}

private Element op(Op o) pure nothrow @nogc
{
    Element e;
    e.op = o;
    return e;
}

private Element offsetElement(string pattern, string noOffsetText, bool lenient) pure nothrow @nogc
{
    Element e;
    e.op = Op.offset;
    e.text = pattern;
    e.noOffsetText = noOffsetText;
    e.lenient = lenient;
    return e;
}

private Element fraction(int min, int max, bool decimalPoint) pure nothrow @nogc
{
    Element e;
    e.op = Op.fraction;
    e.field = Field.nanoOfSecond;
    e.minWidth = cast(ubyte) min;
    e.maxWidth = cast(ubyte) max;
    e.lenient = decimalPoint;
    return e;
}

private immutable Element[] isoLocalDate = [
    num(Field.year, 4, 10, SignStyle.EXCEEDS_PAD), lit("-"), num(Field.monthOfYear, 2), lit("-"),
    num(Field.dayOfMonth, 2)
];
private immutable Element[] isoLocalTime = [
    num(Field.hourOfDay, 2), lit(":"), num(Field.minuteOfHour, 2), op(Op.optionalStart), lit(":"),
    num(Field.secondOfMinute, 2), op(Op.optionalStart), fraction(0, 9, true), op(Op.optionalEnd),
    op(Op.optionalEnd)
];
private immutable Element[] isoLocalDateTime = [op(Op.caseInsensitive)] ~ isoLocalDate ~ [lit("T")] ~ isoLocalTime;
private Element localizedOffsetElement(bool full) pure nothrow @nogc
{
    Element e;
    e.op = Op.localizedOffset;
    e.text = full ? "full" : "short";
    return e;
}

private immutable Element isoOffset = offsetElement("+HH:MM:ss", "Z", true);
private immutable Element isoStrictOffset = offsetElement("+HH:MM:ss", "Z", false);
private immutable Element[] isoOffsetDate = [op(Op.caseInsensitive)] ~ isoLocalDate ~ [
    isoStrictOffset
];
private immutable Element[] isoOffsetTime = [op(Op.caseInsensitive)] ~ isoLocalTime ~ [
    isoStrictOffset
];
private immutable Element[] isoOffsetDateTime = isoLocalDateTime ~ [isoOffset];
private immutable Element[] isoZonedDateTime = isoOffsetDateTime ~ [
    op(Op.optionalStart), lit("["), op(Op.caseSensitive), op(Op.zoneRegion), lit("]"),
    op(Op.optionalEnd)
];
private immutable Element[] isoDateTime = isoLocalDateTime ~ [
    op(Op.optionalStart), isoStrictOffset, op(Op.optionalStart), lit("["), op(Op.caseSensitive),
    op(Op.zoneRegion), lit("]"), op(Op.optionalEnd), op(Op.optionalEnd)
];
private immutable Element[] isoDate = [op(Op.caseInsensitive)] ~ isoLocalDate ~ [
    op(Op.optionalStart), isoStrictOffset, op(Op.optionalEnd)
];
private immutable Element[] isoTime = [op(Op.caseInsensitive)] ~ isoLocalTime ~ [
    op(Op.optionalStart), isoStrictOffset, op(Op.optionalEnd)
];
private immutable Element[] isoOrdinalDate = [
    op(Op.caseInsensitive), num(Field.year, 4, 10, SignStyle.EXCEEDS_PAD), lit("-"),
    num(Field.dayOfYear, 3), op(Op.optionalStart), isoStrictOffset, op(Op.optionalEnd)
];
private immutable Element[] isoWeekDate = [
    op(Op.caseInsensitive), num(Field.weekBasedYear, 4, 10, SignStyle.EXCEEDS_PAD), lit("-W"),
    num(Field.weekOfWeekBasedYear, 2), lit("-"), num(Field.dayOfWeek, 1), op(Op.optionalStart),
    isoStrictOffset, op(Op.optionalEnd)
];
private immutable Element[] isoInstant = [op(Op.caseInsensitive), op(Op.instant)];
private immutable Element[] basicIsoDate = [
    op(Op.caseInsensitive), num(Field.year, 4), num(Field.monthOfYear, 2), num(Field.dayOfMonth,
            2), op(Op.optionalStart), offsetElement("+HHMMss", "Z", true), op(Op.optionalEnd)
];
// RFC 1123 / RFC 822 date-times, parsed leniently: the day-of-week and seconds are optional, and a two-digit year
// is the year itself.
private immutable Element space = lit(" "), colon = lit(":");
private immutable Element[] rfc1123 = [
    op(Op.caseInsensitive), op(Op.lenient), op(Op.optionalStart), textElement(Field.dayOfWeek, 3),
    lit(", "), op(Op.optionalEnd), num(Field.dayOfMonth, 1, 2), space,
    textElement(Field.monthOfYear, 3), space, num(Field.year, 4), space, num(Field.hourOfDay, 2),
    colon, num(Field.minuteOfHour, 2), op(Op.optionalStart), colon, num(Field.secondOfMinute, 2),
    op(Op.optionalEnd), space, offsetElement("+HHMM", "GMT", false)
];
// What the instant element parses: an ISO local date-time with seconds, and an offset. Case sensitivity and
// strictness are the enclosing parse's.
private immutable Element[] instantParse = isoLocalDate ~ [
    lit("T"), num(Field.hourOfDay, 2), lit(":"), num(Field.minuteOfHour, 2), lit(":"),
    num(Field.secondOfMinute, 2), fraction(0, 9, true), isoOffset
];

// Java's descriptions of the ISO formatters, as `DateTimeFormatter.toString` returns them.
private enum describeDate = `Value(Year,4,10,EXCEEDS_PAD)'-'Value(MonthOfYear,2)'-'Value(DayOfMonth,2)`;
private enum describeTime = `Value(HourOfDay,2)':'Value(MinuteOfHour,2)`
    ~ `[':'Value(SecondOfMinute,2)[Fraction(NanoOfSecond,0,9,DecimalPoint)]]`;
private enum describeStrictOffset = `Offset(+HH:MM:ss,'Z')`;
private enum describeOffset = `ParseStrict(false)` ~ describeStrictOffset ~ `ParseStrict(true)`;
private enum describeRegion = `['['ParseCaseSensitive(true)ZoneRegionId()']']`;
private enum describeIsoLocalDate = describeDate;
private enum describeIsoLocalTime = describeTime;
private enum describeIsoOffsetDate = `ParseCaseSensitive(false)(` ~ describeDate ~ `)` ~ describeStrictOffset;
private enum describeIsoOffsetTime = `ParseCaseSensitive(false)(` ~ describeTime ~ `)` ~ describeStrictOffset;
private enum describeIsoLocalDateTime = `ParseCaseSensitive(false)(` ~ describeDate ~ `)'T'(` ~ describeTime ~ `)`;
private enum describeIsoOffsetDateTime = `ParseCaseSensitive(false)(` ~ describeIsoLocalDateTime ~ `)` ~ describeOffset;
private enum describeIsoZonedDateTime = `(` ~ describeIsoOffsetDateTime ~ `)` ~ describeRegion;
private enum describeIsoDateTime = `(` ~ describeIsoLocalDateTime ~ `)[Offset(+HH:MM:ss,'Z')` ~ describeRegion ~ `]`;
private enum describeIsoDate = `ParseCaseSensitive(false)(` ~ describeDate ~ `)[Offset(+HH:MM:ss,'Z')]`;
private enum describeIsoTime = `ParseCaseSensitive(false)(` ~ describeTime ~ `)[Offset(+HH:MM:ss,'Z')]`;
private enum describeIsoOrdinalDate = `ParseCaseSensitive(false)Value(Year,4,10,EXCEEDS_PAD)'-'Value(DayOfYear,3)[`
    ~ describeStrictOffset ~ `]`;
private enum describeIsoWeekDate = `ParseCaseSensitive(false)Value(WeekBasedYear,4,10,EXCEEDS_PAD)'-W'`
    ~ `Value(WeekOfWeekBasedYear,2)'-'Value(DayOfWeek,1)[` ~ describeStrictOffset ~ `]`;
private enum describeIsoInstant = `ParseCaseSensitive(false)Instant()`;
private enum describeRfc1123 = `ParseCaseSensitive(false)ParseStrict(false)[Text(DayOfWeek)', ']`
    ~ `Value(DayOfMonth,1,2,NOT_NEGATIVE)' 'Text(MonthOfYear)' 'Value(Year,4)' 'Value(HourOfDay,2)':'`
    ~ `Value(MinuteOfHour,2)[':'Value(SecondOfMinute,2)]' 'Offset(+HHMM,'GMT')`;
private enum describeBasicIsoDate = `ParseCaseSensitive(false)Value(Year,4)Value(MonthOfYear,2)Value(DayOfMonth,2)`
    ~ `[ParseStrict(false)Offset(+HHMMss,'Z')ParseStrict(true)]`;

/++
Formatter for printing and parsing date-time objects. Java's `DateTimeFormatter` is an immutable final class;
Flint's is an immutable value (ADR-030, R11), so the ISO constants are `static immutable` values.
+/
struct DateTimeFormatter
{
    private immutable(Element)[] elements_;
    private string description_;
    private bool hasZone_;
    private ZoneId zone_;
    private bool smart_;
    private DecimalStyle decimalStyle_;

    /// The ISO date formatter that formats or parses a date without an offset, such as '2011-12-03'.
    static immutable DateTimeFormatter ISO_LOCAL_DATE = DateTimeFormatter(isoLocalDate, describeIsoLocalDate);
    /// The ISO time formatter that formats or parses a time without an offset, such as '10:15' or '10:15:30'.
    static immutable DateTimeFormatter ISO_LOCAL_TIME = DateTimeFormatter(isoLocalTime, describeIsoLocalTime);
    /// The ISO date formatter with a required offset, such as '2011-12-03+01:00'.
    static immutable DateTimeFormatter ISO_OFFSET_DATE = DateTimeFormatter(isoOffsetDate, describeIsoOffsetDate);
    /// The ISO time formatter with a required offset, such as '10:15:30+01:00'.
    static immutable DateTimeFormatter ISO_OFFSET_TIME = DateTimeFormatter(isoOffsetTime, describeIsoOffsetTime);
    /// The ISO date-time formatter without an offset, such as '2011-12-03T10:15:30'.
    static immutable DateTimeFormatter ISO_LOCAL_DATE_TIME = DateTimeFormatter(isoLocalDateTime,
            describeIsoLocalDateTime);
    /// The ISO date-time formatter with an offset, such as '2011-12-03T10:15:30+01:00'.
    static immutable DateTimeFormatter ISO_OFFSET_DATE_TIME = DateTimeFormatter(isoOffsetDateTime,
            describeIsoOffsetDateTime);
    /// The ISO-like date-time formatter with an offset and a bracketed region zone, such as
    /// '2011-12-03T10:15:30+01:00[Europe/Paris]'.
    static immutable DateTimeFormatter ISO_ZONED_DATE_TIME = DateTimeFormatter(isoZonedDateTime,
            describeIsoZonedDateTime);
    /// The ISO-like date-time formatter with the offset and zone if available.
    static immutable DateTimeFormatter ISO_DATE_TIME = DateTimeFormatter(isoDateTime, describeIsoDateTime);
    /// The ISO date formatter with the offset if available, such as '2011-12-03' or '2011-12-03+01:00'.
    static immutable DateTimeFormatter ISO_DATE = DateTimeFormatter(isoDate, describeIsoDate);
    /// The ISO time formatter with the offset if available, such as '10:15:30' or '10:15:30+01:00'.
    static immutable DateTimeFormatter ISO_TIME = DateTimeFormatter(isoTime, describeIsoTime);
    /// The ISO year and day-of-year formatter with an optional offset, such as '2024-060'.
    static immutable DateTimeFormatter ISO_ORDINAL_DATE = DateTimeFormatter(isoOrdinalDate, describeIsoOrdinalDate);
    /// The ISO week-based year, week and day-of-week formatter with an optional offset, such as '2012-W48-6'.
    static immutable DateTimeFormatter ISO_WEEK_DATE = DateTimeFormatter(isoWeekDate, describeIsoWeekDate);
    /// The ISO instant formatter in UTC, such as '2011-12-03T10:15:30Z'.
    static immutable DateTimeFormatter ISO_INSTANT = DateTimeFormatter(isoInstant, describeIsoInstant);
    /// The ISO date formatter without punctuation, such as '20111203'.
    static immutable DateTimeFormatter BASIC_ISO_DATE = DateTimeFormatter(basicIsoDate, describeBasicIsoDate);
    /// The RFC 1123 date-time formatter, such as 'Tue, 3 Jun 2008 11:05:30 GMT'. Parsing is lenient and
    /// resolution SMART; English day and month abbreviations only, and no zone names other than 'GMT'.
    static immutable DateTimeFormatter RFC_1123_DATE_TIME = DateTimeFormatter(rfc1123, describeRfc1123, true);

    private this(immutable(Element)[] elements, string description, bool smart = false) pure nothrow @nogc
    {
        elements_ = elements;
        description_ = description;
        smart_ = smart;
    }

    /**
     * Creates a formatter using the specified pattern, as `DateTimeFormatterBuilder.appendPattern` describes:
     * `u y D M d E a h H m s S n VV X x Z O`, quoted text, `''` and `[ ]` optional sections. Other pattern letters
     * throw `IllegalArgumentException`.
     */
    static DateTimeFormatter ofPattern(string pattern)
    {
        DateTimeFormatterBuilder builder;
        return builder.appendPattern(pattern).toFormatter();
    }

    /// How a parse resolves its fields: `SMART` for `ofPattern` and `RFC_1123_DATE_TIME`, `STRICT` for the ISO
    /// formatters.
    ResolverStyle getResolverStyle() const pure nothrow @nogc
    {
        return smart_ ? ResolverStyle.SMART : ResolverStyle.STRICT;
    }

    /// A copy of this formatter that resolves parsed fields with `style`.
    DateTimeFormatter withResolverStyle(ResolverStyle style) const pure nothrow @nogc
    {
        DateTimeFormatter copy = this;
        copy.smart_ = style == ResolverStyle.SMART;
        return copy;
    }

    /// The override zone, or an absent value when the formatter has no override.
    Nullable!ZoneId getZone() const pure nothrow @nogc
    {
        return hasZone_ ? Nullable!ZoneId(zone_) : Nullable!ZoneId.init;
    }

    /// A copy of this formatter that uses `zone` when printing. Local values keep their date and time fields.
    DateTimeFormatter withZone(ZoneId zone) const pure nothrow @nogc
    {
        DateTimeFormatter copy = this;
        copy.hasZone_ = true;
        copy.zone_ = zone;
        return copy;
    }

    /// A copy with the supplied override. An absent zone clears the override.
    DateTimeFormatter withZone(Nullable!ZoneId zone) const pure nothrow @nogc
    {
        if (!zone.isNull)
            return withZone(zone.get());
        DateTimeFormatter copy = this;
        copy.hasZone_ = false;
        copy.zone_ = ZoneId.init;
        return copy;
    }

    /// The symbols numbers print and parse with: `DecimalStyle.STANDARD` unless `withDecimalStyle` replaced them.
    DecimalStyle getDecimalStyle() const pure nothrow @nogc
    {
        return decimalStyle_;
    }

    /// A copy of this formatter that prints and parses numeric fields and fractions with `decimalStyle`'s zero digit,
    /// signs and decimal separator. Offsets, the instant's printed form and text fields keep ASCII.
    DateTimeFormatter withDecimalStyle(DecimalStyle decimalStyle) const pure nothrow @nogc
    {
        DateTimeFormatter copy = this;
        copy.decimalStyle_ = decimalStyle;
        return copy;
    }

    /// Formats the fields of a temporal value.
    string format(Fields fields) const
    {
        if (hasZone_)
        {
            if (fields.has(Field.instantSeconds))
                fields = zoned(fields);
            else if (!fields.hasOffset_)
                fields.addZone(zone_);
        }
        auto printer = Printer(fields);
        printer.style = decimalStyle_;
        printer.run(elements_);
        return printer.output;
    }

    /// Formats a date-time object: `LocalDate`, `LocalTime`, `LocalDateTime`, `OffsetDateTime`, `ZonedDateTime`
    /// or `Instant`.
    string format(T)(const T temporal) const if (!is(T == Fields))
    {
        return format(Fields.of(temporal));
    }

    private Fields zoned(Fields fields) const
    {
        const instant = Instant.ofEpochSecond(fields.values_[Field.instantSeconds], fields.values_[Field.nanoOfSecond]);
        return Fields.of(instant.atZone(zone_));
    }

    /// Parses the text into fields; throws `DateTimeParseException` with the error index when it does not match.
    Fields parse(string text) const
    {
        return parse(cast(const(char)[]) text);
    }

    /// ditto, from any characters (Java's `CharSequence`): nothing keeps `text`; only an error copies it.
    Fields parse(scope const(char)[] text) const
    {
        Fields fields;
        fields.smart_ = smart_;
        auto parser = Parser(text, &fields);
        parser.style = decimalStyle_;
        const end = parser.run(elements_, 0);
        if (end < 0)
        {
            const index = isExplicitError(end) ? explicitErrorUnits(end) : utf16ErrorIndex(text[0 .. ~end]);
            const copy = text.idup;
            throw new DateTimeParseException("Text '" ~ copy ~ "' could not be parsed at index " ~ indexText(index),
                    copy, index);
        }
        if (end != text.length)
        {
            const index = utf16ErrorIndex(text[0 .. end]);
            const copy = text.idup;
            throw new DateTimeParseException(
                    "Text '" ~ copy ~ "' could not be parsed, unparsed text found at index " ~ indexText(index),
                    copy, index);
        }
        if (hasZone_ && !fields.zoneId_.length)
            fields.addZone(zone_);
        fields.resolveWeekDate(text);
        fields.resolveAll(text);
        return fields;
    }

    /// The printer-parsers, described as Java's `DateTimeFormatter.toString` describes them.
    string toString() const pure nothrow @nogc
    {
        return description_;
    }
}

/++
Builder to create date-time formatters. Java's `DateTimeFormatterBuilder` is a mutable class whose methods return
`this`; Flint's is a struct whose methods return it by `ref` (ADR-030, R12), so Java's chain reads the same:
`DateTimeFormatterBuilder().appendPattern("uuuu-MM-dd").appendLiteral('T').appendOffsetId().toFormatter()`.

Only the methods that take no `TemporalField`, `Locale` or text lookup exist yet. Text is English.
+/
struct DateTimeFormatterBuilder
{
    private Element[] elements_;
    private size_t[] open_; // the index of each optional section not yet ended
    private int[] openPadWidths_; // the pad each open section still owes its next element
    private wchar[] openPadChars_;
    private int padWidth_; // the pad the outermost section still owes its next element
    private wchar padChar_ = ' ';

    /// Changes the parse of the rest of the formatter to be case sensitive, the default.
    ref DateTimeFormatterBuilder parseCaseSensitive() return
    {
        appendElement(op(Op.caseSensitive));
        return this;
    }

    /// Changes the parse of the rest of the formatter to be case insensitive.
    ref DateTimeFormatterBuilder parseCaseInsensitive() return
    {
        appendElement(op(Op.caseInsensitive));
        return this;
    }

    /// Changes the parse of the rest of the formatter to be strict, the default.
    ref DateTimeFormatterBuilder parseStrict() return
    {
        appendElement(op(Op.strict));
        return this;
    }

    /// Changes the parse of the rest of the formatter to be lenient.
    ref DateTimeFormatterBuilder parseLenient() return
    {
        appendElement(op(Op.lenient));
        return this;
    }

    /// Pads the next appended element to `padWidth` with spaces while printing. Throws `IllegalArgumentException`
    /// when the width is less than one.
    ref DateTimeFormatterBuilder padNext(int padWidth) return
    {
        return padNext(padWidth, ' ');
    }

    /// ditto, with `padChar`.
    ref DateTimeFormatterBuilder padNext(int padWidth, wchar padChar) return
    {
        if (padWidth < 1)
            throw new IllegalArgumentException("The pad width must be at least one but was " ~ indexText(padWidth));
        setPad(padWidth, padChar);
        return this;
    }

    // Appends `e` as the next element of the active section, padded when `padNext` set a pad there.
    private void appendElement(Element e)
    {
        if (pendingPad())
        {
            int width;
            wchar padChar;
            takePad(width, padChar);
            Element start = op(Op.padStart);
            start.padWidth = width;
            start.padChar = padChar;
            elements_ ~= start;
            elements_ ~= e;
            elements_ ~= op(Op.padEnd);
            return;
        }
        elements_ ~= e;
    }

    private bool pendingPad() const pure nothrow @nogc
    {
        return open_.length ? openPadWidths_[$ - 1] > 0 : padWidth_ > 0;
    }

    private void setPad(int width, wchar padChar) pure nothrow @nogc
    {
        if (open_.length)
        {
            openPadWidths_[$ - 1] = width;
            openPadChars_[$ - 1] = padChar;
        }
        else
        {
            padWidth_ = width;
            padChar_ = padChar;
        }
    }

    private void takePad(out int width, out wchar padChar) pure nothrow @nogc
    {
        if (open_.length)
        {
            width = openPadWidths_[$ - 1];
            padChar = openPadChars_[$ - 1];
            openPadWidths_[$ - 1] = 0;
            openPadChars_[$ - 1] = ' ';
        }
        else
        {
            width = padWidth_;
            padChar = padChar_;
            padWidth_ = 0;
            padChar_ = ' ';
        }
    }

    /// Appends an instant in ISO-8601 form, in UTC, with the fraction in groups of three digits as needed.
    ref DateTimeFormatterBuilder appendInstant() return
    {
        appendElement(op(Op.instant));
        return this;
    }

    /**
     * Appends an instant in ISO-8601 form, in UTC, with `fractionalDigits` digits of the fraction: -1 for as many as
     * needed, or exactly 0 to 9. Parsing reads exactly that many, or 0 to 9 for -1. Throws `IllegalArgumentException`
     * for any other count.
     */
    ref DateTimeFormatterBuilder appendInstant(int fractionalDigits) return
    {
        if (fractionalDigits < -1 || fractionalDigits > 9)
            throw new IllegalArgumentException(
                    "The fractional digits must be from -1 to 9 inclusive but was " ~ indexText(fractionalDigits));
        auto e = op(Op.instant);
        e.minWidth = cast(ubyte)(fractionalDigits + 2);
        appendElement(e);
        return this;
    }

    /// Appends the zone offset, such as '+01:00', or 'Z' for zero: `appendOffset("+HH:MM:ss", "Z")`.
    ref DateTimeFormatterBuilder appendOffsetId() return
    {
        appendElement(isoStrictOffset);
        return this;
    }

    /**
     * Appends the zone offset in `pattern`, or `noOffsetText` for zero. Throws `IllegalArgumentException` for a
     * pattern Java does not define. The single-digit hour forms, such as `+H:mm`, print one hour digit below ten.
     */
    ref DateTimeFormatterBuilder appendOffset(string pattern, string noOffsetText) return
    {
        static immutable string[22] supported = [
            "+HH", "+HHmm", "+HH:mm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss", "+HHMMSS",
            "+HH:MM:SS", "+HHmmss", "+HH:mm:ss", "+H", "+Hmm", "+H:mm", "+HMM", "+H:MM",
            "+HMMss", "+H:MM:ss", "+HMMSS", "+H:MM:SS", "+Hmmss", "+H:mm:ss"
        ];
        foreach (candidate; supported)
            if (candidate == pattern)
            {
                appendElement(offsetElement(candidate, noOffsetText, false));
                return this;
            }
        throw new IllegalArgumentException("Invalid zone offset pattern: " ~ pattern);
    }

    /**
     * Appends the localized zone offset, such as 'GMT+08:00' for `TextStyle.FULL` or 'GMT+8' for `TextStyle.SHORT`,
     * and 'GMT' for zero. Throws `IllegalArgumentException` for any other style. 'GMT' is the English and root text.
     */
    ref DateTimeFormatterBuilder appendLocalizedOffset(TextStyle style) return
    {
        if (style != TextStyle.FULL && style != TextStyle.SHORT)
            throw new IllegalArgumentException("Style must be either full or short");
        appendElement(localizedOffsetElement(style == TextStyle.FULL));
        return this;
    }

    /// Appends the zone ID, such as 'Europe/Paris' or '+02:00'.
    ref DateTimeFormatterBuilder appendZoneId() return
    {
        appendElement(op(Op.zoneId));
        return this;
    }

    /// Appends a region zone ID, such as 'Europe/Paris'; a value with only an offset does not print one.
    ref DateTimeFormatterBuilder appendZoneRegionId() return
    {
        appendElement(op(Op.zoneRegion));
        return this;
    }

    /// Appends the zone ID when there is one, otherwise the offset: such as 'Europe/Paris', '+02:00' or 'Z'.
    ref DateTimeFormatterBuilder appendZoneOrOffsetId() return
    {
        elements_ ~= op(Op.zoneOrOffset);
        return this;
    }

    /// Appends a character literal. A lone surrogate prints as U+FFFD (R14).
    ref DateTimeFormatterBuilder appendLiteral(wchar literal) return
    {
        char[3] buffer;
        const length = encodeUnit(literal, buffer);
        appendElement(lit(length ? buffer[0 .. length].idup : "\uFFFD"));
        return this;
    }

    /// Appends a string literal; an empty one appends nothing.
    ref DateTimeFormatterBuilder appendLiteral(string literal) return
    {
        if (literal.length)
            appendElement(lit(literal));
        return this;
    }

    /// Appends all the elements of `formatter`. Its zone, decimal style and resolver style are not used.
    ref DateTimeFormatterBuilder append(const DateTimeFormatter formatter) return
    {
        Element start = op(Op.groupStart);
        start.text = formatter.description_;
        appendGroup(start, formatter.elements_, op(Op.groupEnd));
        return this;
    }

    /// Appends `formatter` as an optional section: it prints what is available and parses when it matches.
    ref DateTimeFormatterBuilder appendOptional(const DateTimeFormatter formatter) return
    {
        Element start = op(Op.optionalStart);
        start.lenient = true;
        start.text = formatter.description_;
        appendGroup(start, formatter.elements_, op(Op.optionalEnd));
        return this;
    }

    // Appends `start`, `elements` and `end` as one element of the active section, which `padNext` pads as a whole.
    private void appendGroup(Element start, scope const(Element)[] elements, Element end)
    {
        const padded = pendingPad();
        int width;
        wchar padChar;
        if (padded)
        {
            takePad(width, padChar);
            Element padStart = op(Op.padStart);
            padStart.padWidth = width;
            padStart.padChar = padChar;
            elements_ ~= padStart;
        }
        elements_ ~= start;
        elements_ ~= elements;
        elements_ ~= end;
        if (padded)
            elements_ ~= op(Op.padEnd);
    }

    /**
     * Appends the elements of `pattern`, as `DateTimeFormatter.ofPattern` describes: `u y D M L d E a h H m s S n
     * VV X x Z`, quoted text, `''` and `[ ]` optional sections. A `]` ends an optional section this builder
     * started; one left open stays open. Other pattern letters throw `IllegalArgumentException`.
     */
    ref DateTimeFormatterBuilder appendPattern(string pattern) return
    {
        size_t i;
        while (i < pattern.length)
        {
            const c = pattern[i];
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
            {
                size_t count = 1;
                while (i + count < pattern.length && pattern[i + count] == c)
                    ++count;
                appendElement(letterElement(c, cast(int) count));
                i += count;
            }
            else if (c == '\'')
            {
                string literal;
                i = quoted(pattern, i, literal);
                if (literal.length)
                    appendElement(lit(literal));
            }
            else if (c == '[')
            {
                optionalStart();
                ++i;
            }
            else if (c == ']')
            {
                if (open_.length == 0)
                    throw new IllegalArgumentException("Pattern invalid as it contains ] without previous [");
                endSection();
                ++i;
            }
            else if (c == '{' || c == '}' || c == '#')
                throw new IllegalArgumentException("Pattern includes reserved character: '" ~ c ~ "'");
            else
            {
                size_t next = i;
                decodeUtf8(pattern, next);
                appendElement(lit(pattern[i .. next]));
                i = next;
            }
        }
        return this;
    }

    /// Starts an optional section: it prints when all its fields are available, and parses when it matches.
    ref DateTimeFormatterBuilder optionalStart() return
    {
        open_ ~= elements_.length;
        openPadWidths_ ~= 0;
        openPadChars_ ~= ' ';
        elements_ ~= op(Op.optionalStart);
        return this;
    }

    /// Ends the optional section `optionalStart` started; an empty one is dropped, but still ends adjacent value
    /// parsing, as in Java. Throws `IllegalStateException` when no section is open.
    ref DateTimeFormatterBuilder optionalEnd() return
    {
        if (open_.length == 0)
            throw new IllegalStateException(
                    "Cannot call optionalEnd() as there was no previous call to optionalStart()");
        endSection();
        return this;
    }

    // Ends the open section; appendPattern and toFormatter call it only with one open, so ofPattern does not link
    // IllegalStateException. A section with elements is one element of the enclosing section, which `padNext` pads
    // as a whole; a section's own pending pad is dropped, as Java drops it.
    private void endSection() pure nothrow
    {
        const start = open_[$ - 1];
        open_ = open_[0 .. $ - 1];
        openPadWidths_ = openPadWidths_[0 .. $ - 1];
        openPadChars_ = openPadChars_[0 .. $ - 1];
        foreach (e; elements_[start + 1 .. $])
            if (e.op != Op.adjacentEnd)
            {
                if (pendingPad())
                {
                    int width;
                    wchar padChar;
                    takePad(width, padChar);
                    Element padStart = op(Op.padStart);
                    padStart.padWidth = width;
                    padStart.padChar = padChar;
                    elements_ = elements_[0 .. start] ~ padStart ~ elements_[start .. $] ~ op(
                            Op.optionalEnd) ~ op(Op.padEnd);
                    return;
                }
                elements_ ~= op(Op.optionalEnd);
                return;
            }
        elements_ = elements_[0 .. start] ~ op(Op.adjacentEnd);
    }

    /// Ends any optional sections still open, and creates the formatter, which resolves `SMART`.
    DateTimeFormatter toFormatter()
    {
        while (open_.length)
            endSection();
        return DateTimeFormatter(elements_.idup, describeElements(elements_), true);
    }
}

private immutable string[SignStyle.max + 1] signNames = [
    "NORMAL", "ALWAYS", "NEVER", "NOT_NEGATIVE", "EXCEEDS_PAD"
];

// Java's toString of the printer-parsers of `ofPattern` and `DateTimeFormatterBuilder`. An appended formatter is
// its own description, in brackets when optional and in parentheses otherwise.
private string describeElements(scope const(Element)[] elements) pure
{
    string text;
    for (size_t i = 0; i < elements.length; ++i)
    {
        const e = elements[i];
        if (e.op == Op.padStart)
        {
            const end = sectionEnd(elements, i);
            text ~= "Pad(" ~ describeElements(elements[i + 1 .. end]) ~ "," ~ indexText(e.padWidth);
            if (e.padChar != ' ')
                text ~= ",'" ~ padCharText(e.padChar) ~ "'";
            text ~= ")";
            i = end;
        }
        else if (e.op == Op.groupStart || (e.op == Op.optionalStart && e.lenient))
        {
            text ~= e.op == Op.groupStart ? "(" ~ e.text ~ ")" : "[" ~ e.text ~ "]";
            i = sectionEnd(elements, i);
        }
        else
            text ~= describeElement(e);
    }
    return text;
}

// The UTF-8 form of a pad character, as `DateTimeFormatterBuilder`'s `Pad` description writes it.
private string padCharText(wchar unit) pure nothrow
{
    char[3] buffer;
    const length = encodeUnit(unit, buffer);
    return length ? buffer[0 .. length].idup : "\uFFFD";
}

private immutable string[Op.max - Op.optionalStart + 1] controlNames = [
    "[", "]", "ParseCaseSensitive(false)", "ParseCaseSensitive(true)", "ParseStrict(false)",
    "ParseStrict(true)", "(", ")", "", "", ""
];

// Op.zoneId, Op.zoneRegion, Op.zoneOrOffset and Op.instant.
private immutable string[4] zoneInstantNames = [
    "ZoneId()", "ZoneRegionId()", "ZoneOrOffsetId()", "Instant()"
];

private string describeElement(const Element e) pure
{
    if (e.op == Op.number || e.op == Op.fraction)
        return describeNumber(e);
    if (e.op >= Op.optionalStart)
        return controlNames[e.op - Op.optionalStart];
    if (e.op >= Op.zoneId)
        return zoneInstantNames[e.op - Op.zoneId];
    switch (e.op)
    {
    case Op.reducedYear:
        return "ReducedValue(" ~ fieldNames[e.field] ~ ",2,2,2000-01-01)";
    case Op.literal:
        return e.text == "'" ? "''" : "'" ~ doubledQuotes(e.text) ~ "'";
    case Op.text:
        return "Text(" ~ fieldNames[e.field] ~ (e.text == "full" ? ")" : ",SHORT)");
    case Op.localizedOffset:
        return e.text == "full" ? "LocalizedOffset(FULL)" : "LocalizedOffset(SHORT)";
    default:
        return "Offset(" ~ e.text ~ ",'" ~ doubledQuotes(e.noOffsetText) ~ "')";
    }
}

// `text` with each `'` doubled, as `DateTimeFormatterBuilder`'s literal printer writes it.
private string doubledQuotes(string text) pure nothrow
{
    string doubled;
    foreach (c; text)
    {
        if (c == '\'')
            doubled ~= "''";
        else
            doubled ~= c;
    }
    return doubled;
}

// The ASCII upper case of `c`; any other character as it is.
private char asciiUpper(char c) pure nothrow @nogc
{
    return c >= 'a' && c <= 'z' ? cast(char)(c - ('a' - 'A')) : c;
}

private string describeNumber(const Element e) pure
{
    import flint.engine.aot.text : decimal;

    const min = decimal(cast(int) e.minWidth), max = decimal(cast(int) e.maxWidth);
    if (e.op == Op.fraction)
        return "Fraction(NanoOfSecond," ~ min ~ "," ~ max ~ (e.lenient ? ",DecimalPoint)" : ")");
    if (e.minWidth == 1 && e.maxWidth == 19 && e.sign == SignStyle.NORMAL)
        return "Value(" ~ fieldNames[e.field] ~ ")";
    if (e.minWidth == e.maxWidth && e.sign == SignStyle.NOT_NEGATIVE)
        return "Value(" ~ fieldNames[e.field] ~ "," ~ min ~ ")";
    return "Value(" ~ fieldNames[e.field] ~ "," ~ min ~ "," ~ max ~ "," ~ signNames[e.sign] ~ ")";
}

private int utf16ErrorIndex(scope const(char)[] prefix) pure nothrow @nogc
{
    size_t offset;
    int units;
    while (offset < prefix.length)
        units += decodeUtf8(prefix, offset) > 0xFFFF ? 2 : 1;
    return units;
}

// A parse result is `~position` for a failure at a byte position. Java's pad decorator can report an error index
// past the end of the text, so it is carried as the UTF-16 index Java reports instead.
private enum explicitErrorBase = 0x4000_0000;
private int explicitError(int units) pure nothrow @nogc
{
    return -(explicitErrorBase + units);
}

private bool isExplicitError(int encoded) pure nothrow @nogc
{
    return encoded <= -explicitErrorBase;
}

private int explicitErrorUnits(int encoded) pure nothrow @nogc
{
    return -encoded - explicitErrorBase;
}

// The byte offset of the UTF-16 unit `units` into `text`, rounded up to the next code point boundary when `units`
// falls inside a surrogate pair.
private int byteAtUnit(scope const(char)[] text, int units) pure nothrow @nogc
{
    size_t position;
    int count;
    while (position < text.length)
    {
        size_t next = position;
        const units_ = decodeUtf8(text, next) > 0xFFFF ? 2 : 1;
        count += units_;
        if (count >= units)
            return cast(int) next;
        position = next;
    }
    return cast(int) text.length;
}

private string indexText(int index) pure nothrow
{
    import flint.engine.aot.text : decimal;

    return decimal(index);
}

private string padded(long value, int width) pure nothrow
{
    import flint.engine.aot.text : decimal;

    auto digits = decimal(value);
    while (digits.length < width)
        digits = "0" ~ digits;
    return digits;
}

private struct Printer
{
    Fields fields;
    string output;
    bool caseInsensitive;
    DecimalStyle style;

    // Appends one symbol of the decimal style; a lone surrogate is written as U+FFFD (R14).
    void put(wchar unit) pure nothrow
    {
        char[3] buffer;
        const length = encodeUnit(unit, buffer);
        output ~= length ? buffer[0 .. length] : "\uFFFD";
    }

    // Appends ASCII digits in the decimal style's digits: each is the zero digit plus its value, as a UTF-16 unit.
    void putDigits(scope const(char)[] digits) pure nothrow
    {
        if (style.zeroDigit_ == '0')
        {
            output ~= digits;
            return;
        }
        foreach (c; digits)
            put(cast(wchar)(style.zeroDigit_ + (c - '0')));
    }

    // Prints the elements; returns false when a field is missing in an optional section.
    bool run(scope const(Element)[] elements, bool optional = false)
    {
        for (size_t i = 0; i < elements.length; ++i)
        {
            const e = elements[i];
            // An appended formatter, like an optional section, drops what it printed when a field is missing in an
            // optional section, and what follows it still prints.
            if (e.op == Op.optionalStart || e.op == Op.groupStart)
            {
                const end = sectionEnd(elements, i);
                const mark = output.length;
                if (!run(elements[i + 1 .. end], optional || e.op == Op.optionalStart))
                    output = output[0 .. mark];
                i = end;
                continue;
            }
            if (e.op == Op.padStart)
            {
                const end = sectionEnd(elements, i);
                const mark = output.length;
                if (!run(elements[i + 1 .. end], optional))
                {
                    output = output[0 .. mark];
                    return false;
                }
                padOutput(mark, e.padWidth, e.padChar);
                i = end;
                continue;
            }
            if (!print(e))
            {
                if (optional)
                    return false;
                if (e.op == Op.zoneId)
                    throw new DateTimeException("Unable to extract ZoneId from temporal " ~ fields.describe());
                if (e.op == Op.zoneOrOffset)
                    throw new DateTimeException("Unable to extract Zone from temporal " ~ fields.describe());
                throw new DateTimeException("Unsupported field: " ~ missingField(e));
            }
        }
        return true;
    }

    // Pads what was printed from `mark` to `width` with `padChar`, as Java's `PadPrinterParserDecorator`.
    void padOutput(size_t mark, int width, wchar padChar)
    {
        const units = utf16ErrorIndex(output[mark .. $]);
        if (units > width)
            throw new DateTimeException("Cannot print as output of " ~ indexText(
                    units) ~ " characters exceeds pad width of " ~ indexText(width));
        if (units < width)
            output = output[0 .. mark] ~ padText(padChar, width - units) ~ output[mark .. $];
    }

    string missingField(const Element e) const pure nothrow @nogc
    {
        switch (e.op)
        {
        case Op.offset:
        case Op.localizedOffset:
            return "OffsetSeconds";
        case Op.zoneId:
        case Op.zoneRegion:
        case Op.zoneOrOffset:
            return "ZoneId";
        case Op.instant:
            return "InstantSeconds";
        default:
            return fieldNames[e.field];
        }
    }

    bool print(const Element e)
    {
        if (e.op >= Op.optionalStart)
            return true;
        if (e.op >= Op.zoneId && e.op < Op.instant)
            return printZone(e);
        switch (e.op)
        {
        case Op.number:
            return printNumber(e);
        case Op.reducedYear:
            return printReducedYear(e);
        case Op.fraction:
            return printFraction(e);
        case Op.literal:
            output ~= e.text;
            return true;
        case Op.text:
            return printText(e);
        case Op.offset:
        case Op.localizedOffset:
            return printOffset(e);
        default:
            return printInstant(e);
        }
    }

    bool printReducedYear(const Element e)
    {
        if (!fields.has(e.field))
            return false;
        putDigits(padded(((fields.values_[e.field] % 100) + 100) % 100, 2));
        return true;
    }

    bool printZone(const Element e)
    {
        if (fields.zoneId_.length != 0)
        {
            if (e.op == Op.zoneRegion && !fields.zoneIsRegion_)
                return false;
            output ~= fields.zoneId_;
            return true;
        }
        // ZoneOrOffsetId, unlike ZoneId, prints an offset when there is no zone ID.
        if (e.op == Op.zoneOrOffset && fields.hasOffset_)
        {
            output ~= formatOffset(fields.offsetSeconds_, "+HH:MM:ss", "Z");
            return true;
        }
        return false;
    }

    bool printNumber(const Element e)
    {
        import flint.engine.aot.text : decimal;

        long value;
        if (!fields.printedValue(e.field, value))
            return false;
        const magnitude = value < 0 ? -value : value;
        auto digits = padded(magnitude, e.minWidth);
        if (digits.length > e.maxWidth)
        {
            const shown = decimal(value), width = decimal(cast(int) e.maxWidth);
            throw new DateTimeException("Field " ~ fieldNames[e.field]
                    ~ " cannot be printed as the value " ~ shown ~ " exceeds the maximum print width of " ~ width);
        }
        final switch (e.sign)
        {
        case SignStyle.EXCEEDS_PAD:
            if (value < 0)
                put(style.negativeSign_);
            else if (e.minWidth < 19 && value >= tenPow(e.minWidth))
                put(style.positiveSign_);
            break;
        case SignStyle.ALWAYS:
            put(value < 0 ? style.negativeSign_ : style.positiveSign_);
            break;
        case SignStyle.NORMAL:
            if (value < 0)
                put(style.negativeSign_);
            break;
        case SignStyle.NOT_NEGATIVE:
            if (value < 0)
            {
                const field = fieldNames[e.field], shown = decimal(value);
                throw new DateTimeException("Field " ~ field ~ " cannot be printed as the value "
                        ~ shown ~ " cannot be negative according to the SignStyle");
            }
            break;
        case SignStyle.NEVER:
            break;
        }
        putDigits(digits);
        return true;
    }

    bool printFraction(const Element e)
    {
        if (!fields.has(Field.nanoOfSecond))
            return false;
        auto digits = padded(fields.values_[Field.nanoOfSecond], 9)[0 .. e.maxWidth];
        while (digits.length > e.minWidth && digits[$ - 1] == '0')
            digits = digits[0 .. $ - 1];
        if (digits.length == 0)
            return true;
        if (e.lenient)
            put(style.decimalSeparator_);
        putDigits(digits);
        return true;
    }

    bool printText(const Element e)
    {
        if (!fields.has(e.field))
            return false;
        const value = cast(size_t) fields.values_[e.field];
        const full = e.text == "full";
        switch (e.field)
        {
        case Field.monthOfYear:
            output ~= full ? monthFull[value - 1] : monthFull[value - 1][0 .. 3];
            break;
        case Field.dayOfWeek:
            output ~= full ? dayFull[value - 1] : dayFull[value - 1][0 .. 3];
            break;
        default:
            output ~= value == 0 ? "AM" : "PM";
            break;
        }
        return true;
    }

    bool printOffset(const Element e)
    {
        if (e.op == Op.localizedOffset)
            return printLocalizedOffset(e);
        if (!fields.hasOffset_)
            return false;
        output ~= formatOffset(fields.offsetSeconds_, e.text, e.noOffsetText);
        return true;
    }

    // 'GMT', then for a non-zero offset its sign and hours, minutes and seconds: FULL prints "+HH:MM" and ":SS" when
    // the seconds are not zero; SHORT prints the hours without padding and ":MM" or ":MM:SS" only when not zero.
    bool printLocalizedOffset(const Element e)
    {
        if (!fields.hasOffset_)
            return false;
        output ~= "GMT";
        const totalSeconds = fields.offsetSeconds_;
        if (totalSeconds == 0)
            return true;
        const total = totalSeconds < 0 ? -totalSeconds : totalSeconds;
        const hours = total / 3600 % 100, minutes = total / 60 % 60, seconds = total % 60;
        output ~= totalSeconds < 0 ? "-" : "+";
        if (e.text == "full")
        {
            output ~= padded(hours, 2) ~ ":" ~ padded(minutes, 2);
            if (seconds != 0)
                output ~= ":" ~ padded(seconds, 2);
            return true;
        }
        output ~= padded(hours, 1);
        if (minutes != 0 || seconds != 0)
        {
            output ~= ":" ~ padded(minutes, 2);
            if (seconds != 0)
                output ~= ":" ~ padded(seconds, 2);
        }
        return true;
    }

    // As Java: `appendInstant()` prints the fraction in groups of three as needed, as `Instant.toString`; -1
    // fractional digits prints as many as needed, and 0 to 9 exactly that many.
    bool printInstant(const Element e)
    {
        if (!fields.has(Field.instantSeconds))
            return false;
        const nano = fields.has(Field.nanoOfSecond) ? fields.values_[Field.nanoOfSecond] : 0;
        if (e.minWidth == 0)
        {
            output ~= Instant.ofEpochSecond(fields.values_[Field.instantSeconds], nano).toString();
            return true;
        }
        const whole = Instant.ofEpochSecond(fields.values_[Field.instantSeconds]).toString();
        output ~= whole[0 .. $ - 1]; // without the 'Z'
        const digits = e.minWidth - 2;
        if (digits > 0 || (digits < 0 && nano > 0))
        {
            const fraction = padded(nano, 9);
            size_t length = digits < 0 ? 9 : digits;
            while (digits < 0 && fraction[length - 1] == '0') // a non-zero nano ends the loop
                --length;
            output ~= "." ~ fraction[0 .. length];
        }
        output ~= "Z";
        return true;
    }
}

// The UTF-8 form of one UTF-16 unit in `buffer`; returns its length, or 0 for a lone surrogate.
private size_t encodeUnit(wchar unit, ref char[3] buffer) pure nothrow @nogc
{
    if (unit < 0x80)
    {
        buffer[0] = cast(char) unit;
        return 1;
    }
    if (unit < 0x800)
    {
        buffer[0] = cast(char)(0xC0 | (unit >> 6));
        buffer[1] = cast(char)(0x80 | (unit & 0x3F));
        return 2;
    }
    if (unit >= 0xD800 && unit <= 0xDFFF)
        return 0;
    buffer[0] = cast(char)(0xE0 | (unit >> 12));
    buffer[1] = cast(char)(0x80 | ((unit >> 6) & 0x3F));
    buffer[2] = cast(char)(0x80 | (unit & 0x3F));
    return 3;
}

private long tenPow(int n) pure nothrow @nogc
{
    long p = 1;
    foreach (_; 0 .. n)
        p *= 10;
    return p;
}

// `count` copies of `padChar` in UTF-8; a lone surrogate prints as U+FFFD (R14).
private string padText(wchar padChar, int count) pure nothrow
{
    string text;
    char[3] buffer;
    const length = encodeUnit(padChar, buffer);
    foreach (_; 0 .. count)
        text ~= length ? buffer[0 .. length] : "\uFFFD";
    return text;
}

private immutable string[12] monthFull = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December"
];
private immutable string[7] dayFull = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
];

// The index of the end matching the optionalStart, groupStart or padStart at `start`, or the end of the list.
private size_t sectionEnd(scope const(Element)[] elements, size_t start) pure nothrow @nogc
{
    const open = elements[start].op;
    const close = open == Op.optionalStart ? Op.optionalEnd : open == Op.groupStart ? Op.groupEnd : Op.padEnd;
    int depth;
    foreach (i; start .. elements.length)
    {
        if (elements[i].op == open)
            ++depth;
        else if (elements[i].op == close && --depth == 0)
            return i;
    }
    return elements.length;
}

private struct OffsetShape
{
    bool paddedHour;
    bool minutes;
    bool minutesOptional;
    bool seconds;
    bool secondsOptional;
    bool colon;
}

// "+HH", "+HHmm", "+HH:mm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss", "+HHMMSS", "+HH:MM:SS", "+HHmmss",
// "+HH:mm:ss", and the single-digit hour forms "+H", "+Hmm", "+H:mm", "+HMM", "+H:MM", "+HMMss", "+H:MM:ss",
// "+HMMSS", "+H:MM:SS", "+Hmmss", "+H:mm:ss".
private OffsetShape offsetShape(string pattern) pure nothrow @nogc
{
    OffsetShape shape;
    shape.paddedHour = pattern.length > 2 && pattern[2] == 'H';
    const hourEnd = shape.paddedHour ? 3 : 2;
    shape.colon = pattern.length > hourEnd && pattern[hourEnd] == ':';
    const restStart = shape.colon ? hourEnd + 1 : hourEnd;
    const rest = pattern.length > restStart ? pattern[restStart .. $] : "";
    shape.minutes = rest.length >= 2;
    shape.minutesOptional = shape.minutes && rest[0] == 'm';
    const tail = rest.length > 2 ? rest[shape.colon ? 3 : 2 .. $] : "";
    shape.seconds = tail.length >= 2;
    shape.secondsOptional = shape.seconds && tail[0] == 's';
    return shape;
}

private string formatOffset(int totalSeconds, string pattern, string noOffsetText) pure nothrow
{
    if (totalSeconds == 0)
        return noOffsetText;
    const shape = offsetShape(pattern);
    const total = totalSeconds < 0 ? -totalSeconds : totalSeconds;
    const hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60;
    // As Java, a single-digit hour pattern prints one digit below 10, and two from 10.
    const hourWidth = shape.paddedHour || hours >= 10 ? 2 : 1;
    auto text = (totalSeconds < 0 ? "-" : "+") ~ padded(hours, hourWidth);
    const separator = shape.colon ? ":" : "";
    const printMinutes = shape.minutes && (!shape.minutesOptional || minutes != 0 || seconds != 0);
    const printSeconds = printMinutes && shape.seconds && (!shape.secondsOptional || seconds != 0);
    if (printMinutes)
        text ~= separator ~ padded(minutes, 2);
    if (printSeconds)
        text ~= separator ~ padded(seconds, 2);
    // An offset that prints as all zeros, such as +00:00:45 as +HHMM, prints the no-offset text.
    return zeroDigits(text[1 .. $]) ? noOffsetText : text;
}

private bool zeroDigits(scope const(char)[] text) pure nothrow @nogc
{
    foreach (c; text)
        if (c != '0' && c != ':')
            return false;
    return true;
}

private struct Parser
{
    const(char)[] text;
    Fields* fields; // the caller's: the parser borrows `text`, so the result lives outside it
    bool caseInsensitive;
    bool lenient;
    DecimalStyle style;

    // Parses the elements from `position`; returns the end position, or `~errorIndex` on failure.
    int run(scope const(Element)[] elements, int position) scope
    {
        for (size_t i = 0; i < elements.length; ++i)
        {
            const e = elements[i];
            if (e.op == Op.optionalStart)
            {
                // As Java, a failed section restores the parsed fields; its settings stay.
                const end = sectionEnd(elements, i);
                const saved = *fields;
                const next = run(elements[i + 1 .. end], position);
                if (next < 0)
                    *fields = saved;
                else
                    position = next;
                i = end;
                continue;
            }
            if (e.op == Op.padStart)
            {
                const end = sectionEnd(elements, i);
                const next = parsePad(elements[i + 1 .. end], e, position);
                if (next < 0)
                    return next;
                position = next;
                i = end;
                continue;
            }
            position = parseOne(e, elements[i + 1 .. $], position);
            if (position < 0)
                return position;
        }
        return position;
    }

    // Java's pad decorator: skip up to `padWidth` pad characters, then parse the wrapped element within those
    // characters. A strict parse needs the whole width; a lenient one treats the width as a maximum.
    int parsePad(scope const(Element)[] elements, const Element pad, int position) scope
    {
        const strict = !lenient;
        if (position >= text.length)
            return ~position;
        const startUnits = utf16ErrorIndex(text[0 .. position]);
        const totalUnits = startUnits + utf16ErrorIndex(text[position .. $]);
        const target = startUnits + pad.padWidth;
        if (strict && target > totalUnits)
            return ~position;
        const end = byteAtUnit(text, target > totalUnits ? totalUnits : target);
        int pos = position;
        while (pos < end)
        {
            const length = padLength(pos, pad.padChar);
            if (length == 0)
                break;
            pos += length;
        }
        const saved = text;
        Parser bounded = Parser(text[0 .. end], fields);
        bounded.caseInsensitive = caseInsensitive;
        bounded.lenient = lenient;
        bounded.style = style;
        const next = bounded.run(elements, pos);
        // Settings the wrapped elements changed stay changed, as they do in Java's parse context.
        caseInsensitive = bounded.caseInsensitive;
        lenient = bounded.lenient;
        // As Java, a strict parse that does not end exactly at the pad width fails at the start of the wrapped
        // element plus the start again, whether the wrapped element parsed short or failed. A lenient parse returns
        // the wrapped parse's own result, even a failure.
        if (strict && next != end)
            return explicitError(2 * startUnits + utf16ErrorIndex(saved[position .. pos]));
        return next;
    }

    // The UTF-8 length of the pad character at `at`, or 0 when the text there is not it. As Java, the match folds
    // case when the parse is case insensitive; only ASCII folds here.
    int padLength(size_t at, wchar padChar) scope const pure nothrow @nogc
    {
        size_t next = at;
        const c = decodeUtf8(text, next);
        if (c == padChar || (caseInsensitive && c <= 0x7F && padChar <= 0x7F
                && asciiUpper(cast(char) c) == asciiUpper(cast(char) padChar)))
            return cast(int)(next - at);
        return 0;
    }

    int control(const Element e, int position) scope pure nothrow @nogc
    {
        if (e.op == Op.caseInsensitive)
            caseInsensitive = true;
        else if (e.op == Op.caseSensitive)
            caseInsensitive = false;
        else if (e.op == Op.lenient || e.op == Op.strict)
            lenient = e.op == Op.lenient;
        return position;
    }

    int parseOne(const Element e, scope const(Element)[] following, int position) scope
    {
        if (e.op >= Op.optionalStart)
            return control(e, position);
        if (e.op >= Op.zoneId && e.op < Op.instant)
            return parseZone(position);
        switch (e.op)
        {
        case Op.number:
            return parseNumber(e, following, position);
        case Op.reducedYear:
            return parseReducedYear(e, position);
        case Op.fraction:
            return parseFraction(e, position);
        case Op.literal:
            return parseLiteral(e.text, position);
        case Op.text:
            return parseText(e, position);
        case Op.offset:
        case Op.localizedOffset:
            return parseOffset(e, position);
        default:
            return parseInstant(e, position);
        }
    }

    // Java's instant parser: an ISO local date-time with seconds, a fraction of exactly the fractional digits, or 0 to
    // 9 digits for -1 and `appendInstant()`, and an offset. For 0 digits Java's fraction parser refuses its width, and
    // the parse fails with that message at index 0.
    int parseInstant(const Element e, int position) scope
    {
        if (e.minWidth < 2)
            return run(instantParse, position);
        if (e.minWidth == 2)
        {
            const copy = text.idup;
            throw new DateTimeParseException(
                    "Text '" ~ copy ~ "' could not be parsed: Maximum width must be from 1 to 9 inclusive but was 0",
                    copy, 0);
        }
        Element[instantParse.length] elements = instantParse;
        elements[$ - 2] = fraction(e.minWidth - 2, e.minWidth - 2, true);
        return run(elements[], position);
    }

    static bool digit(char c) pure nothrow @nogc
    {
        return c >= '0' && c <= '9';
    }

    // The value of the decimal style's digit at `position`, setting `length` to its UTF-8 length; -1 when the
    // character there is not one. As Java, a digit is a UTF-16 unit zero to nine above the zero digit.
    int digitAt(size_t position, out int length) scope const pure nothrow @nogc
    {
        if (position >= text.length)
            return -1;
        if (style.zeroDigit_ == '0')
        {
            length = 1;
            return digit(text[position]) ? text[position] - '0' : -1;
        }
        size_t next = position;
        const c = decodeUtf8(text, next);
        length = cast(int)(next - position);
        const value = cast(int) c - style.zeroDigit_;
        return c <= 0xFFFF && value >= 0 && value <= 9 ? value : -1;
    }

    // The UTF-8 length of `unit` when the text at `position` is that symbol, or 0. A lone surrogate never matches
    // UTF-8 text.
    int symbolAt(wchar unit, size_t position) scope const pure nothrow @nogc
    {
        char[3] buffer;
        const length = encodeUnit(unit, buffer);
        const end = position + length;
        if (length == 0 || end > text.length || text[position .. end] != buffer[0 .. length])
            return 0;
        return cast(int) length;
    }

    // Digits reserved for the fixed-width numbers that directly follow (adjacent value parsing).
    static int reserved(scope const(Element)[] following) pure nothrow @nogc
    {
        int total;
        foreach (e; following)
        {
            if (e.op == Op.number || e.op == Op.reducedYear)
                total += e.op == Op.reducedYear ? 2 : e.minWidth;
            else if (e.op == Op.fraction && !e.lenient)
                total += e.minWidth;
            else
                break;
        }
        return total;
    }

    // The decimal style's sign at `position`, setting `length` to its UTF-8 length: 0 for none, 1 for positive,
    // -1 for negative, or 2 when the sign style rejects it. The positive sign is tried first. A strict parse rejects
    // a positive sign for NORMAL. A lenient parse needs no sign for ALWAYS, and accepts one for NOT_NEGATIVE and NEVER
    // unless the width is fixed.
    int sign(const Element e, int position, out int length) scope const pure nothrow @nogc
    {
        const positive = symbolAt(style.positiveSign_, position);
        length = positive ? positive : symbolAt(style.negativeSign_, position);
        if (length == 0)
            return e.sign == SignStyle.ALWAYS && !lenient ? 2 : 0;
        if ((e.sign == SignStyle.NOT_NEGATIVE || e.sign == SignStyle.NEVER) && !(lenient && e.minWidth != e.maxWidth))
            return 2;
        if (e.sign == SignStyle.NORMAL && positive && !lenient)
            return 2;
        return positive ? 1 : -1;
    }

    // The digits a value takes when `spare` remain after those reserved for the values that follow. With too few
    // for them, it still takes its minimum width.
    static int width(int spare, int minWidth, int maxWidth) pure nothrow @nogc
    {
        return spare < minWidth ? minWidth : spare > maxWidth ? maxWidth : spare;
    }

    // EXCEEDS_PAD parsed strictly: '+' only for more digits than the minimum width, which then need a sign.
    static bool padSignMismatch(bool plus, bool signed, int digits, int minWidth) pure nothrow @nogc
    {
        return (plus && digits <= minWidth) || (!signed && digits > minWidth);
    }

    int parseNumber(const Element e, scope const(Element)[] following, int position) scope
    {
        int signLength;
        const signValue = sign(e, position, signLength);
        if (signValue == 2)
            return ~position;
        const negative = signValue < 0, signed = signValue != 0;
        const pos = position + signLength;
        const available = digitCount(pos);
        const reserve = reserved(following);
        // A lenient parse reads a value that no fixed-width value follows as one to nine digits.
        const variable = lenient && reserve == 0;
        const minWidth = variable ? 1 : e.minWidth, maxWidth = variable ? 9 : e.maxWidth;
        if (available < minWidth)
            return ~pos;
        const take = width(available - reserve, minWidth, maxWidth);
        if (!lenient && e.sign == SignStyle.EXCEEDS_PAD && padSignMismatch(signed && !negative,
                signed, take, e.minWidth))
            return ~position;
        int end = pos;
        const value = digitsValue(take, end);
        // A strict parse rejects a negative zero at its sign.
        if (negative && value == 0 && !lenient)
            return ~position;
        fields.set(e.field, negative ? -value : value);
        return end;
    }

    // The number of the decimal style's digits from `position`.
    int digitCount(int position) scope const pure nothrow @nogc
    {
        int count, length;
        for (size_t at = position; digitAt(at, length) >= 0; at += length)
            ++count;
        return count;
    }

    // The value of `count` digits from `end`, which moves past them.
    long digitsValue(int count, ref int end) scope const pure nothrow @nogc
    {
        long value;
        int length;
        foreach (_; 0 .. count)
        {
            value = value * 10 + digitAt(end, length);
            end += length;
        }
        return value;
    }

    int parseReducedYear(const Element e, int position) scope
    {
        // NOT_NEGATIVE with a fixed width: a sign is rejected, even one that is also a digit.
        if (symbolAt(style.positiveSign_, position) || symbolAt(style.negativeSign_, position))
            return ~position;
        int first, second;
        const tens = digitAt(position, first);
        const units = tens < 0 ? -1 : digitAt(position + first, second);
        if (units < 0)
            return ~position;
        fields.set(e.field, 2000 + tens * 10 + units);
        return position + first + second;
    }

    int parseFraction(const Element e, int position) scope
    {
        int pos = position;
        if (e.lenient)
        {
            const separator = symbolAt(style.decimalSeparator_, pos);
            if (separator == 0)
                return e.minWidth > 0 ? ~position : position;
            pos += separator;
        }
        int count, end = pos, length, d;
        long value;
        while (count < e.maxWidth && (d = digitAt(end, length)) >= 0)
        {
            value = value * 10 + d;
            end += length;
            ++count;
        }
        if (count < e.minWidth || (e.lenient && count == 0))
            return ~pos;
        fields.set(Field.nanoOfSecond, value * tenPow(9 - count));
        return end;
    }

    bool matches(string expected, int position) scope const pure nothrow @nogc
    {
        if (position + expected.length > text.length)
            return false;
        foreach (i, c; expected)
        {
            const a = text[position + i];
            if (a != c && !(caseInsensitive && (a | 0x20) == (c | 0x20) && ((c | 0x20) >= 'a' && (c | 0x20) <= 'z')))
                return false;
        }
        return true;
    }

    int parseLiteral(string expected, int position) scope pure nothrow @nogc
    {
        return matches(expected, position) ? position + cast(int) expected.length : ~position;
    }

    int parseText(const Element e, int position) scope
    {
        const full = e.text == "full";
        static immutable string[2] amPm = ["AM", "PM"];
        const(string)[] names = e.field == Field.monthOfYear ? monthFull[] : e.field == Field.dayOfWeek
            ? dayFull[] : amPm[];
        foreach (i, name; names)
        {
            const candidate = full || e.field == Field.amPmOfDay ? name : name[0 .. 3];
            if (matches(candidate, position))
            {
                fields.set(e.field, e.field == Field.amPmOfDay ? cast(long) i : cast(long) i + 1);
                return position + cast(int) candidate.length;
            }
        }
        // A lenient parse falls back to the field's number.
        return lenient ? parseNumber(num(e.field, 1, 19, SignStyle.NORMAL), null, position) : ~position;
    }

    int twoDigits(int position) scope const pure nothrow @nogc
    {
        if (position + 2 > text.length || !digit(text[position]) || !digit(text[position + 1]))
            return -1;
        return (text[position] - '0') * 10 + (text[position + 1] - '0');
    }

    // One optional `[:]dd` group of an offset; returns the new position, unchanged when absent.
    int offsetGroup(int position, bool colon, ref int value) scope const pure nothrow @nogc
    {
        int pos = position;
        if (colon && (pos >= text.length || text[pos] != ':'))
            return position;
        if (colon)
            ++pos;
        const v = twoDigits(pos);
        if (v < 0 || v > 59)
            return position;
        value = v;
        return pos + 2;
    }

    int parseOffset(const Element e, int position) scope
    {
        if (e.op == Op.localizedOffset)
            return parseLocalizedOffset(e, position);
        // As Java, empty no-offset text matches only at the end, or where no offset can be read.
        if (e.noOffsetText.length ? matches(e.noOffsetText, position) : position == text.length)
            return setOffset(0, position, position + cast(int) e.noOffsetText.length);
        if (position >= text.length || (text[position] != '+' && text[position] != '-'))
            return noOffset(e, position);
        const sign = text[position] == '-' ? -1 : 1;
        int[3] parts; // hours, minutes, seconds
        const end = offsetGroups(e, position, parts);
        if (end < 0)
            return noOffset(e, position);
        if (parts[0] > 23 || parts[1] > 59 || parts[2] > 59)
            throw Fields.failed(text,
                    new DateTimeException("Value out of range: Hour[0-23], Minute[0-59], Second[0-59]"));
        return setOffset(sign * (parts[0] * 3600 + parts[1] * 60 + parts[2]), position, end);
    }

    // The offset groups after the sign at `position`, into hours, minutes and seconds; returns the end, or -1.
    int offsetGroups(const Element e, int position, ref int[3] parts) scope
    {
        if (offsetShape(e.text).paddedHour)
            return paddedOffset(e, position, parts);
        return unpaddedOffset(e, position, parts);
    }

    // A two-digit hour pattern, as Java reads each group as two digits up to 59. Returns the end, or -1.
    int paddedOffset(const Element e, int position, ref int[3] parts) scope
    {
        const hours = twoDigits(position + 1);
        if (hours < 0 || hours > 59)
            return -1;
        int[2] ms;
        const end = offsetMinutesSeconds(e, position + 3, ms);
        if (end < 0)
            return -1;
        parts[0] = hours;
        parts[1] = ms[0];
        parts[2] = ms[1];
        return end;
    }

    // A single-digit hour offset pattern, as OpenJDK's OffsetIdPrinterParser reads it: one or two hour digits, then
    // the minutes and seconds the pattern names. `sign` is the index of the '+' or '-'; returns the end, or -1.
    int unpaddedOffset(const Element e, int sign, ref int[3] parts) scope
    {
        const shape = offsetShape(e.text);
        const lenient = e.lenient || this.lenient;
        const start = sign + 1;
        if (lenient)
        {
            // Java remaps a lenient parse to colon-separated groups when the text shows a colon, else to a
            // variable-width 1-6 digit form.
            const colon = shape.colon || (e.text == "+H" && text.length > start + 2
                    && (text[start + 1] == ':' || text[start + 2] == ':'));
            if (colon)
                return colonOffset(start, false, true, false, parts);
            return variableOffset(start, 1, 6, parts);
        }
        if (!shape.minutes)
            return variableOffset(start, 1, 2, parts);
        if (!shape.colon)
        {
            // The variable-width forms: +Hmm (1-4), +HMM (3-4), +HMMss (3-6), +HMMSS (5-6), +Hmmss (1-6).
            int minDigits = 1, maxDigits = 6;
            if (!shape.seconds)
            {
                minDigits = shape.minutesOptional ? 1 : 3;
                maxDigits = 4;
            }
            else if (!shape.secondsOptional)
            {
                minDigits = 5;
                maxDigits = 6;
            }
            else
            {
                minDigits = shape.minutesOptional ? 1 : 3;
                maxDigits = 6;
            }
            return variableOffset(start, minDigits, maxDigits, parts);
        }
        // Colon forms: +H:mm (optional minute), +H:MM (mandatory), +H:MM:ss (optional second),
        // +H:MM:SS (mandatory), +H:mm:ss (optional minute and second).
        return colonOffset(start, !shape.minutesOptional, shape.seconds, shape.seconds
                && !shape.secondsOptional, parts);
    }

    // A run of `minDigits` to `maxDigits` digits split into hours, minutes and seconds, as Java's
    // parseVariableWidthDigits. Returns the end, or -1 when too few digits are present.
    int variableOffset(int position, int minDigits, int maxDigits, ref int[3] parts) scope const pure nothrow @nogc
    {
        int pos = position;
        char[6] digits;
        int available;
        while (available < maxDigits && pos < text.length && text[pos] >= '0' && text[pos] <= '9')
            digits[available++] = text[pos++];
        if (available < minDigits)
            return -1;
        switch (available)
        {
        case 1:
            parts[0] = digits[0] - '0';
            break;
        case 2:
            parts[0] = (digits[0] - '0') * 10 + (digits[1] - '0');
            break;
        case 3:
            parts[0] = digits[0] - '0';
            parts[1] = (digits[1] - '0') * 10 + (digits[2] - '0');
            break;
        case 4:
            parts[0] = (digits[0] - '0') * 10 + (digits[1] - '0');
            parts[1] = (digits[2] - '0') * 10 + (digits[3] - '0');
            break;
        case 5:
            parts[0] = digits[0] - '0';
            parts[1] = (digits[1] - '0') * 10 + (digits[2] - '0');
            parts[2] = (digits[3] - '0') * 10 + (digits[4] - '0');
            break;
        default:
            parts[0] = (digits[0] - '0') * 10 + (digits[1] - '0');
            parts[1] = (digits[2] - '0') * 10 + (digits[3] - '0');
            parts[2] = (digits[4] - '0') * 10 + (digits[5] - '0');
            break;
        }
        return pos;
    }

    // One or two hour digits, then optional or mandatory ":MM" and ":SS" groups, as Java's parseHour followed by
    // its colon group reads. `hasSeconds` is whether the pattern names a seconds group. Returns the end, or -1 when
    // a mandatory group is missing.
    int colonOffset(int position, bool mandatoryMinute, bool hasSeconds, bool mandatorySecond, ref int[3] parts) scope
    {
        const hourEnd = variableOffset(position, 1, 2, parts);
        if (hourEnd < 0)
            return -1;
        const minuteEnd = offsetGroup(hourEnd, true, parts[1]);
        if (minuteEnd == hourEnd)
            return mandatoryMinute ? -1 : hourEnd;
        if (!hasSeconds)
            return minuteEnd;
        const secondEnd = offsetGroup(minuteEnd, true, parts[2]);
        if (secondEnd == minuteEnd)
            return mandatorySecond ? -1 : minuteEnd;
        return secondEnd;
    }

    // A lenient "+HH" reads colon-separated groups when the text has a colon after the hours, as Java.
    bool colonAfterHours(const Element e, int pos, bool lenient) scope const pure nothrow @nogc
    {
        return lenient && e.text == "+HH" && pos < text.length && text[pos] == ':';
    }

    // Sets the parsed offset and returns `end`; as Java, an offset already parsed with another value fails at
    // `position`.
    int setOffset(int seconds, int position, int end) scope pure nothrow @nogc
    {
        if (fields.hasOffset_ && fields.offsetSeconds_ != seconds)
            return ~position;
        fields.hasOffset_ = true;
        fields.offsetSeconds_ = seconds;
        return end;
    }

    // Where no offset can be read: a zero offset for empty no-offset text, otherwise an error.
    int noOffset(const Element e, int position) scope pure nothrow @nogc
    {
        return e.noOffsetText.length ? ~position : setOffset(0, position, position);
    }

    // 'GMT' and an optional signed offset, read as Java reads it. FULL needs "HH:MM" and reads ":SS"; SHORT reads one
    // or two hour digits, then ":MM" and ":SS". An optional group is read only when the whole group fits in the text.
    // Where Java reads past the end of the text, the parse fails as Java's does with its IndexOutOfBoundsException.
    int parseLocalizedOffset(const Element e, int position) scope
    {
        if (!matches("GMT", position))
            return ~position;
        const start = position + 3; // the sign; Java's positions from here count UTF-16 units
        const end = utf16ErrorIndex(text[start .. $]);
        if (end == 0)
            return setOffset(0, position, start);
        const sign = unitAfter(start, 0);
        if (sign != '+' && sign != '-')
            return setOffset(0, position, start);
        int[3] hms;
        const pos = e.text == "full" ? fullOffset(start, end, hms) : shortOffset(start, end, hms);
        if (pos < 0)
            return ~position;
        // Every unit read on success is ASCII, so `pos` units are `pos` bytes.
        return setOffset((sign == '-' ? -1 : 1) * (hms[0] * 3600 + hms[1] * 60 + hms[2]), position, start + pos);
    }

    // FULL's "HH:MM" and optional ":SS" after the sign at `start`; returns the units read, or -1.
    int fullOffset(int start, int end, ref int[3] hms) scope
    {
        int pos = 1;
        const h1 = offsetDigit(start, pos++, end), h2 = offsetDigit(start, pos++, end);
        if (h1 < 0 || h2 < 0 || offsetUnit(start, pos++, end) != ':')
            return -1;
        const m1 = offsetDigit(start, pos++, end), m2 = offsetDigit(start, pos++, end);
        if (m1 < 0 || m2 < 0)
            return -1;
        hms[0] = h1 * 10 + h2;
        hms[1] = m1 * 10 + m2;
        return offsetGroupAfter(start, pos, end, hms[2]);
    }

    // SHORT's one or two hour digits and optional ":MM" and ":SS" after the sign at `start`; returns the units read,
    // or -1.
    int shortOffset(int start, int end, ref int[3] hms) scope
    {
        int pos = 1;
        hms[0] = offsetDigit(start, pos++, end);
        if (hms[0] < 0)
            return -1;
        if (pos >= end)
            return pos;
        const h2 = offsetDigit(start, pos, end);
        if (h2 >= 0)
        {
            hms[0] = hms[0] * 10 + h2;
            ++pos;
        }
        const next = offsetGroupAfter(start, pos, end, hms[1]);
        return next == pos ? pos : offsetGroupAfter(start, next, end, hms[2]);
    }

    // Java's ":" and two digits at `pos` units after `start`, read only when `pos + 2 < end`; returns the position
    // after them, or `pos` without them.
    int offsetGroupAfter(int start, int pos, int end, out int value) scope
    {
        if (pos + 2 >= end || unitAfter(start, pos) != ':')
            return pos;
        const d1 = offsetDigit(start, pos + 1, end), d2 = offsetDigit(start, pos + 2, end);
        if (d1 < 0 || d2 < 0)
            return pos;
        value = d1 * 10 + d2;
        return pos + 3;
    }

    // The ASCII digit `k` UTF-16 units after the byte index `start`, or -1 for any other character.
    int offsetDigit(int start, int k, int end) scope
    {
        const unit = offsetUnit(start, k, end);
        return unit >= '0' && unit <= '9' ? unit - '0' : -1;
    }

    // Java's `charAt` of the unit `k` UTF-16 units after the byte index `start`, which counts `end` units to the end
    // of the text: as Java, an index past the end fails the parse with Java's out-of-bounds message.
    int offsetUnit(int start, int k, int end) scope
    {
        if (k < end)
            return unitAfter(start, k);
        const copy = text.idup;
        const offset = utf16ErrorIndex(text[0 .. start]);
        const message = "Index " ~ indexText(offset + k) ~ " out of bounds for length " ~ indexText(offset + end);
        throw new DateTimeParseException("Text '" ~ copy ~ "' could not be parsed: " ~ message, copy, 0);
    }

    // The UTF-16 unit `k` units after the byte index `start`: an ASCII character as it is, and 0xFFFF for any unit
    // outside ASCII. The caller keeps `k` within the text.
    int unitAfter(int start, int k) scope const pure nothrow @nogc
    {
        size_t pos = start;
        while (pos < text.length)
        {
            const c = decodeUtf8(text, pos);
            const units = c > 0xFFFF ? 2 : 1;
            if (k < units)
                return c < 0x80 ? cast(int) c : 0xFFFF;
            k -= units;
        }
        return 0xFFFF;
    }

    // The minutes and seconds groups after an offset's hours; returns the end, or -1 when a required group is
    // missing.
    int offsetMinutesSeconds(const Element e, int pos, ref int[2] parts) scope const pure nothrow @nogc
    {
        auto shape = offsetShape(e.text);
        const lenient = e.lenient || this.lenient;
        shape.colon |= colonAfterHours(e, pos, lenient);
        if (!shape.minutes && !lenient)
            return pos;
        const next = offsetGroup(pos, shape.colon, parts[0]);
        if (next == pos)
            return shape.minutes && !shape.minutesOptional && !lenient ? -1 : pos;
        if (!shape.seconds && !lenient)
            return next;
        const after = offsetGroup(next, shape.colon, parts[1]);
        if (after == next && shape.seconds && !shape.secondsOptional && !lenient)
            return -1;
        return after;
    }

    int parseZone(int position) scope
    {
        int end = position;
        while (end < text.length && zoneChar(text[end]))
            ++end;
        if (end == position)
            return ~position;
        try
            fields.zoneId_ = ZoneId.of(text[position .. end].idup).getId();
        catch (DateTimeException)
            return ~position;
        fields.zoneIsRegion_ = !ZoneId.of(fields.zoneId_).isOffset();
        // A parsed fixed offset is both a zone and an offset, as Java's ZoneOffset is, so resolution can obtain the
        // offset field from it.
        if (!fields.zoneIsRegion_)
            return setOffset(ZoneOffset.of(fields.zoneId_).getTotalSeconds(), position, end);
        return end;
    }

    static bool zoneChar(char c) pure nothrow @nogc
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || digit(c) || c == '/' || c == '_'
            || c == '+' || c == '-' || c == '.' || c == '~' || c == ':';
    }
}

// A quoted literal starting at `start`; `''` is a single quote. Returns the index after the closing quote, and the
// literal to append in `literal` (empty when there is none).
private size_t quoted(string pattern, size_t start, out string literal)
{
    literal = null;
    if (start + 1 < pattern.length && pattern[start + 1] == '\'')
    {
        literal = "'";
        return start + 2;
    }
    string text;
    size_t i = start + 1;
    for (;;)
    {
        if (i >= pattern.length)
            throw new IllegalArgumentException("Pattern ends with an incomplete string literal: " ~ pattern);
        if (pattern[i] == '\'')
        {
            if (i + 1 < pattern.length && pattern[i + 1] == '\'')
            {
                text ~= '\'';
                i += 2;
                continue;
            }
            break;
        }
        text ~= pattern[i++];
    }
    literal = text;
    return i + 1;
}

private Element textElement(Field f, int count) pure nothrow @nogc
{
    Element e;
    e.op = Op.text;
    e.field = f;
    e.text = count >= 4 ? "full" : "short";
    return e;
}

private Element yearElement(Field f, int count) pure nothrow @nogc
{
    if (count == 2)
    {
        Element e;
        e.op = Op.reducedYear;
        e.field = f;
        return e;
    }
    if (count < 4)
        return num(f, count, 19, SignStyle.NORMAL);
    return num(f, count, 19, SignStyle.EXCEEDS_PAD);
}

private Element twoWide(Field f, char c, int count)
{
    if (count == 1)
        return num(f, 1, 19, SignStyle.NORMAL);
    if (count == 2)
        return num(f, count);
    throw new IllegalArgumentException("Too many pattern letters: " ~ c);
}

private Element letterElement(char c, int count)
{
    static immutable string twoWideLetters = "dHhms";
    static immutable Field[5] twoWideFields = [
        Field.dayOfMonth, Field.hourOfDay, Field.clockHourOfAmPm, Field.minuteOfHour,
        Field.secondOfMinute
    ];
    foreach (i, letter; twoWideLetters)
        if (letter == c)
            return twoWide(twoWideFields[i], c, count);
    return dateLetter(c, count);
}

private Element dateLetter(char c, int count)
{
    switch (c)
    {
    case 'u':
        return yearElement(Field.year, count);
    case 'y':
        return yearElement(Field.yearOfEra, count);
    case 'M':
    case 'L':
        return count <= 2 ? twoWide(Field.monthOfYear, c, count) : textElement(Field.monthOfYear, count);
    case 'D':
        if (count > 3)
            throw new IllegalArgumentException("Too many pattern letters: D");
        return count == 1 ? num(Field.dayOfYear, 1, 19, SignStyle.NORMAL) : num(Field.dayOfYear, count, 3);
    case 'E':
        return textElement(Field.dayOfWeek, count);
    default:
        return timeLetter(c, count);
    }
}

private Element timeLetter(char c, int count)
{
    switch (c)
    {
    case 'a':
        if (count > 1)
            throw new IllegalArgumentException("Too many pattern letters: a");
        return textElement(Field.amPmOfDay, count);
    case 'S':
        if (count > 9)
            throw new IllegalArgumentException("Too many pattern letters: S");
        return fraction(count, count, false);
    case 'n':
        return num(Field.nanoOfSecond, count, 19, SignStyle.NOT_NEGATIVE);
    default:
        return zoneLetter(c, count);
    }
}

private Element zoneLetter(char c, int count)
{
    static immutable string[5] xPatterns = ["+HHmm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss"];
    static immutable string[5] xZero = ["+00", "+0000", "+00:00", "+0000", "+00:00"];
    switch (c)
    {
    case 'V':
        if (count != 2)
            throw new IllegalArgumentException("Pattern letter count must be 2: V");
        return op(Op.zoneId);
    case 'X':
    case 'x':
        if (count > 5)
            throw new IllegalArgumentException("Too many pattern letters: " ~ c);
        return offsetElement(xPatterns[count - 1], c == 'X' ? "Z" : xZero[count - 1], false);
    default:
        return offsetLetter(c, count);
    }
}

private Element offsetLetter(char c, int count)
{
    switch (c)
    {
    case 'Z':
        if (count < 4)
            return offsetElement("+HHMM", "+0000", false);
        if (count == 4)
            return localizedOffsetElement(true);
        if (count == 5)
            return offsetElement("+HH:MM:ss", "Z", false);
        throw new IllegalArgumentException("Too many pattern letters: Z");
    case 'O':
        if (count == 1 || count == 4)
            return localizedOffsetElement(count == 4);
        throw new IllegalArgumentException("Pattern letter count must be 1 or 4: O");
    default:
        throw new IllegalArgumentException("Pattern letter not supported by Flint yet: " ~ c);
    }
}

/// Parses a duration in the ISO-8601 form `PnDTnHnMn.nS`, as `Duration.parse` specifies.
Duration parseDuration(string text)
{
    size_t pos;
    bool negate;
    if (pos < text.length && (text[pos] == '+' || text[pos] == '-'))
        negate = text[pos++] == '-';
    if (pos >= text.length || asciiUpper(text[pos]) != 'P')
        throw durationError(text);
    ++pos;
    long seconds, nanos;
    bool any, inTime;
    while (pos < text.length)
    {
        if (asciiUpper(text[pos]) == 'T')
        {
            if (inTime)
                throw durationError(text);
            inTime = true;
            ++pos;
            if (pos == text.length)
                throw durationError(text);
            continue;
        }
        const part = durationPart(text, pos, inTime);
        seconds += part.seconds;
        nanos += part.nanos;
        any = true;
    }
    if (!any)
        throw durationError(text);
    try
    {
        const result = Duration.ofSeconds(seconds, nanos);
        return negate ? result.negated() : result;
    }
    catch (ArithmeticException e)
        throw new DateTimeParseException("Text cannot be parsed to a Duration: overflow", text, 0, e);
}

private DateTimeParseException durationError(string text) pure nothrow
{
    return new DateTimeParseException("Text cannot be parsed to a Duration", text, 0);
}

private struct DurationPart
{
    long seconds;
    long nanos;
}

// The optional `.n` or `,n` fraction of seconds at `pos`, in nanoseconds; advances `pos` past it.
private long durationFraction(string text, ref size_t pos)
{
    if (pos >= text.length || (text[pos] != '.' && text[pos] != ','))
        return 0;
    ++pos;
    size_t count;
    long nanos;
    while (pos < text.length && Parser.digit(text[pos]) && count < 9)
    {
        nanos = nanos * 10 + (text[pos++] - '0');
        ++count;
    }
    if (count == 0)
        throw durationError(text);
    return nanos * tenPow(cast(int)(9 - count));
}

// One `[-]n[.n]X` component; advances `pos` past its unit letter.
private DurationPart durationPart(string text, ref size_t pos, bool inTime)
{
    const start = pos;
    const negative = pos < text.length && text[pos] == '-';
    if (pos < text.length && (text[pos] == '-' || text[pos] == '+'))
        ++pos;
    long whole;
    size_t digits;
    while (pos < text.length && Parser.digit(text[pos]))
    {
        whole = whole * 10 + (text[pos++] - '0');
        ++digits;
    }
    const fractionNanos = durationFraction(text, pos);
    if (digits == 0 || pos >= text.length)
        throw durationError(text);
    const unit = asciiUpper(text[pos++]);
    const sign = negative ? -1 : 1;
    const seconds = unitSeconds(unit, inTime);
    if (seconds == 0 || (fractionNanos != 0 && unit != 'S'))
    {
        pos = start;
        throw durationError(text);
    }
    return DurationPart(sign * whole * seconds, sign * fractionNanos);
}

// Seconds per unit of a duration component: D before the 'T', H, M and S after it; 0 when not allowed.
private long unitSeconds(char unit, bool inTime) pure nothrow @nogc
{
    if (!inTime)
        return unit == 'D' ? 86_400 : 0;
    return unit == 'H' ? 3600 : unit == 'M' ? 60 : unit == 'S' ? 1 : 0;
}
