/++
Java's `java.time.format`: `DateTimeFormatter`, its ISO constants and `ofPattern`, and `DateTimeParseException`.

Written clean-room from the Java SE 21 API specification of `DateTimeFormatter` and `DateTimeFormatterBuilder`.
A formatter is a list of printer-parser elements, as the specification describes: numeric fields with a width and
sign style, fractions, literals, text, offsets, zone IDs, the instant, and optional sections. English text only;
`Locale` arguments are not supported yet.

`Fields` stands in for `TemporalAccessor`: the erased set of fields one value supplies to a formatter, or one parse
produces.
+/
module flint.java.time.format;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : IllegalArgumentException;
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
    zoneId,
    zoneRegion,
    instant,
    // Control elements: everything from here on prints nothing.
    optionalStart,
    optionalEnd,
    caseInsensitive,
    caseSensitive,
    lenient,
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
// What the instant element parses: an ISO local date-time with seconds, and an offset.
private immutable Element[] instantParse = [op(Op.caseInsensitive)] ~ isoLocalDate ~ [
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
     * `u y D M d E a h H m s S n VV X x Z`, quoted text, `''` and `[ ]` optional sections. Other pattern letters
     * throw `IllegalArgumentException`.
     */
    static DateTimeFormatter ofPattern(string pattern)
    {
        auto elements = compilePattern(pattern);
        return DateTimeFormatter(elements.idup, describeElements(elements), true);
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
        DateTimeFormatter copy = DateTimeFormatter(elements_, description_, smart_);
        copy.hasZone_ = true;
        copy.zone_ = zone;
        return copy;
    }

    /// A copy with the supplied override. An absent zone clears the override.
    DateTimeFormatter withZone(Nullable!ZoneId zone) const pure nothrow @nogc
    {
        return zone.isNull ? DateTimeFormatter(elements_, description_, smart_) : withZone(zone.get());
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
        const end = parser.run(elements_, 0);
        if (end < 0)
        {
            const index = utf16ErrorIndex(text[0 .. ~end]);
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

private immutable string[SignStyle.max + 1] signNames = [
    "NORMAL", "ALWAYS", "NEVER", "NOT_NEGATIVE", "EXCEEDS_PAD"
];

// Java's toString of the printer-parsers of `ofPattern`.
private string describeElements(scope const(Element)[] elements) pure
{
    string text;
    foreach (e; elements)
        text ~= describeElement(e);
    return text;
}

private string describeElement(const Element e) pure
{
    if (e.op == Op.number || e.op == Op.fraction)
        return describeNumber(e);
    if (e.op >= Op.optionalStart)
        return e.op == Op.optionalStart ? "[" : e.op == Op.optionalEnd ? "]" : "";
    switch (e.op)
    {
    case Op.reducedYear:
        return "ReducedValue(" ~ fieldNames[e.field] ~ ",2,2,2000-01-01)";
    case Op.literal:
        return e.text == "'" ? "''" : "'" ~ doubledQuotes(e.text) ~ "'";
    case Op.text:
        return "Text(" ~ fieldNames[e.field] ~ (e.text == "full" ? ")" : ",SHORT)");
    case Op.offset:
        return "Offset(" ~ e.text ~ ",'" ~ e.noOffsetText ~ "')";
    default:
        return "ZoneId()";
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

    // Prints the elements; returns false when a field is missing in an optional section.
    bool run(scope const(Element)[] elements, bool optional = false)
    {
        for (size_t i = 0; i < elements.length; ++i)
        {
            const e = elements[i];
            if (e.op == Op.optionalStart)
            {
                const end = sectionEnd(elements, i);
                const mark = output.length;
                if (!run(elements[i + 1 .. end], true))
                    output = output[0 .. mark];
                i = end;
                continue;
            }
            if (!print(e))
            {
                if (optional)
                    return false;
                if (e.op == Op.zoneId)
                    throw new DateTimeException("Unable to extract ZoneId from temporal " ~ fields.describe());
                throw new DateTimeException("Unsupported field: " ~ missingField(e));
            }
        }
        return true;
    }

    string missingField(const Element e) const pure nothrow @nogc
    {
        switch (e.op)
        {
        case Op.offset:
            return "OffsetSeconds";
        case Op.zoneId:
        case Op.zoneRegion:
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
            return printOffset(e);
        case Op.zoneId:
        case Op.zoneRegion:
            return printZone(e.op == Op.zoneRegion);
        default:
            return printInstant();
        }
    }

    bool printReducedYear(const Element e)
    {
        if (!fields.has(e.field))
            return false;
        output ~= padded(((fields.values_[e.field] % 100) + 100) % 100, 2);
        return true;
    }

    bool printZone(bool regionOnly)
    {
        if (fields.zoneId_.length == 0 || (regionOnly && !fields.zoneIsRegion_))
            return false;
        output ~= fields.zoneId_;
        return true;
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
                output ~= "-";
            else if (e.minWidth < 19 && value >= tenPow(e.minWidth))
                output ~= "+";
            break;
        case SignStyle.ALWAYS:
            output ~= value < 0 ? "-" : "+";
            break;
        case SignStyle.NORMAL:
            if (value < 0)
                output ~= "-";
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
        output ~= digits;
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
            output ~= ".";
        output ~= digits;
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
        if (!fields.hasOffset_)
            return false;
        output ~= formatOffset(fields.offsetSeconds_, e.text, e.noOffsetText);
        return true;
    }

    bool printInstant()
    {
        if (!fields.has(Field.instantSeconds))
            return false;
        const nano = fields.has(Field.nanoOfSecond) ? fields.values_[Field.nanoOfSecond] : 0;
        output ~= Instant.ofEpochSecond(fields.values_[Field.instantSeconds], nano).toString();
        return true;
    }
}

private long tenPow(int n) pure nothrow @nogc
{
    long p = 1;
    foreach (_; 0 .. n)
        p *= 10;
    return p;
}

private immutable string[12] monthFull = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December"
];
private immutable string[7] dayFull = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
];

// The index of the optionalEnd matching the optionalStart at `start`, or the end of the list.
private size_t sectionEnd(scope const(Element)[] elements, size_t start) pure nothrow @nogc
{
    int depth;
    foreach (i; start .. elements.length)
    {
        if (elements[i].op == Op.optionalStart)
            ++depth;
        else if (elements[i].op == Op.optionalEnd && --depth == 0)
            return i;
    }
    return elements.length;
}

private struct OffsetShape
{
    bool minutes;
    bool minutesOptional;
    bool seconds;
    bool secondsOptional;
    bool colon;
}

// "+HH", "+HHmm", "+HH:mm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss", "+HHMMSS", "+HH:MM:SS".
private OffsetShape offsetShape(string pattern) pure nothrow @nogc
{
    OffsetShape shape;
    shape.colon = pattern.length > 3 && pattern[3] == ':';
    const rest = pattern.length > 3 ? pattern[shape.colon ? 4 : 3 .. $] : "";
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
    auto text = (totalSeconds < 0 ? "-" : "+") ~ padded(hours, 2);
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

    // Parses the elements from `position`; returns the end position, or `~errorIndex` on failure.
    int run(scope const(Element)[] elements, int position) scope
    {
        for (size_t i = 0; i < elements.length; ++i)
        {
            const e = elements[i];
            if (e.op == Op.optionalStart)
            {
                const end = sectionEnd(elements, i);
                const saved = *fields;
                const savedCase = caseInsensitive, savedLenient = lenient;
                const next = run(elements[i + 1 .. end], position);
                if (next < 0)
                {
                    *fields = saved;
                    caseInsensitive = savedCase;
                    lenient = savedLenient;
                }
                else
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

    int control(const Element e, int position) scope pure nothrow @nogc
    {
        if (e.op == Op.caseInsensitive)
            caseInsensitive = true;
        else if (e.op == Op.caseSensitive)
            caseInsensitive = false;
        else if (e.op == Op.lenient)
            lenient = true;
        return position;
    }

    int parseOne(const Element e, scope const(Element)[] following, int position) scope
    {
        if (e.op >= Op.optionalStart)
            return control(e, position);
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
            return parseOffset(e, position);
        case Op.zoneId:
        case Op.zoneRegion:
            return parseZone(position);
        default:
            return run(instantParse, position);
        }
    }

    static bool digit(char c) pure nothrow @nogc
    {
        return c >= '0' && c <= '9';
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

    // The sign at `position`: 0 for none, 1 for '+', -1 for '-', or 2 when the sign style rejects it. A lenient
    // parse needs no sign for ALWAYS, and accepts one for NOT_NEGATIVE and NEVER unless the width is fixed.
    int sign(const Element e, int position) scope const pure nothrow @nogc
    {
        const present = position < text.length && (text[position] == '+' || text[position] == '-');
        if (!present)
            return e.sign == SignStyle.ALWAYS && !lenient ? 2 : 0;
        if ((e.sign == SignStyle.NOT_NEGATIVE || e.sign == SignStyle.NEVER) && !(lenient && e.minWidth != e.maxWidth))
            return 2;
        return text[position] == '-' ? -1 : 1;
    }

    // EXCEEDS_PAD parsed strictly: '+' only for more digits than the minimum width, which then need a sign.
    static bool padSignMismatch(bool plus, bool signed, int digits, int minWidth) pure nothrow @nogc
    {
        return (plus && digits <= minWidth) || (!signed && digits > minWidth);
    }

    int parseNumber(const Element e, scope const(Element)[] following, int position) scope
    {
        const signValue = sign(e, position);
        if (signValue == 2)
            return ~position;
        const negative = signValue < 0, signed = signValue != 0;
        const pos = signed ? position + 1 : position;
        int available;
        while (pos + available < text.length && digit(text[pos + available]))
            ++available;
        const reserve = reserved(following);
        // A lenient parse reads a value that no fixed-width value follows as one to nine digits.
        const variable = lenient && reserve == 0;
        const minWidth = variable ? 1 : e.minWidth, maxWidth = variable ? 9 : e.maxWidth;
        int take = available - reserve;
        take = take > maxWidth ? maxWidth : take;
        if (take < minWidth)
            return ~pos;
        if (!lenient && e.sign == SignStyle.EXCEEDS_PAD && padSignMismatch(signed && !negative,
                signed, take, e.minWidth))
            return ~position;
        long value;
        foreach (c; text[pos .. pos + take])
            value = value * 10 + (c - '0');
        fields.set(e.field, negative ? -value : value);
        return pos + take;
    }

    int parseReducedYear(const Element e, int position) scope
    {
        if (position + 2 > text.length || !digit(text[position]) || !digit(text[position + 1]))
            return ~position;
        fields.set(e.field, 2000 + (text[position] - '0') * 10 + (text[position + 1] - '0'));
        return position + 2;
    }

    int parseFraction(const Element e, int position) scope
    {
        int pos = position;
        if (e.lenient)
        {
            if (pos >= text.length || text[pos] != '.')
                return e.minWidth > 0 ? ~position : position;
            ++pos;
        }
        int count;
        long value;
        while (count < e.maxWidth && pos + count < text.length && digit(text[pos + count]))
        {
            value = value * 10 + (text[pos + count] - '0');
            ++count;
        }
        if (count < e.minWidth || (e.lenient && count == 0))
            return ~pos;
        fields.set(Field.nanoOfSecond, value * tenPow(9 - count));
        return pos + count;
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
        if (e.noOffsetText.length && matches(e.noOffsetText, position))
        {
            fields.hasOffset_ = true;
            fields.offsetSeconds_ = 0;
            return position + cast(int) e.noOffsetText.length;
        }
        if (position >= text.length || (text[position] != '+' && text[position] != '-'))
            return ~position;
        const sign = text[position] == '-' ? -1 : 1;
        // Java reads each group as two digits up to 59; hours 24 to 59 are then out of range.
        const hours = twoDigits(position + 1);
        if (hours < 0 || hours > 59)
            return ~position;
        int[2] parts;
        const end = offsetMinutesSeconds(e, position + 3, parts);
        if (end < 0)
            return ~position;
        if (hours > 23)
            throw Fields.failed(text,
                    new DateTimeException("Value out of range: Hour[0-23], Minute[0-59], Second[0-59]"));
        fields.hasOffset_ = true;
        fields.offsetSeconds_ = sign * (hours * 3600 + parts[0] * 60 + parts[1]);
        return end;
    }

    // The minutes and seconds groups after an offset's hours; returns the end, or -1 when a required group is
    // missing.
    int offsetMinutesSeconds(const Element e, int pos, ref int[2] parts) scope const pure nothrow @nogc
    {
        const shape = offsetShape(e.text);
        const lenient = e.lenient || this.lenient;
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
        return end;
    }

    static bool zoneChar(char c) pure nothrow @nogc
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || digit(c) || c == '/' || c == '_'
            || c == '+' || c == '-' || c == '.' || c == '~' || c == ':';
    }
}

// Compiles an `ofPattern` pattern into elements.
private Element[] compilePattern(string pattern)
{
    Element[] elements;
    size_t i;
    int depth;
    while (i < pattern.length)
    {
        const c = pattern[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
        {
            size_t count = 1;
            while (i + count < pattern.length && pattern[i + count] == c)
                ++count;
            elements ~= letterElement(c, cast(int) count);
            i += count;
        }
        else if (c == '\'')
            i = quoted(pattern, i, elements);
        else if (c == '[')
        {
            ++depth;
            elements ~= op(Op.optionalStart);
            ++i;
        }
        else if (c == ']')
        {
            if (depth-- == 0)
                throw new IllegalArgumentException("Pattern invalid as it contains ] without previous [");
            elements ~= op(Op.optionalEnd);
            ++i;
        }
        else if (c == '{' || c == '}' || c == '#')
            throw new IllegalArgumentException("Pattern includes reserved character: '" ~ c ~ "'");
        else
        {
            elements ~= lit(pattern[i .. i + 1]);
            ++i;
        }
    }
    foreach (_; 0 .. depth)
        elements ~= op(Op.optionalEnd);
    return elements;
}

// A quoted literal starting at `start`; `''` is a single quote. Returns the index after the closing quote.
private size_t quoted(string pattern, size_t start, ref Element[] elements)
{
    if (start + 1 < pattern.length && pattern[start + 1] == '\'')
    {
        elements ~= lit("'");
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
    if (text.length)
        elements ~= lit(text);
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
    case 'Z':
        if (count < 4)
            return offsetElement("+HHMM", "+0000", false);
        if (count == 5)
            return offsetElement("+HH:MM:ss", "Z", false);
        throw new IllegalArgumentException("Pattern letter not supported by Flint yet: ZZZZ");
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
    const result = Duration.ofSeconds(seconds, nanos);
    return negate ? result.negated() : result;
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
