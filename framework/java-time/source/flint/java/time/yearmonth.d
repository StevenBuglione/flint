/// Clean-room Java SE 21 ISO year and month values.
module flint.java.time.yearmonth;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : NullPointerException;
import flint.java.time : DateTimeException, LocalDate, Month, checkRange, getValue, isLeap;
import flint.java.time.format : DateTimeParseException;

@safe:

private enum int minYear = -999_999_999;
private enum int maxYear = 999_999_999;

/// A month in a proleptic Gregorian calendar year. The D default is January 1970.
struct YearMonth
{
    private int year_ = 1970;
    private ubyte month_ = 1;

    private this(int year, int month) pure nothrow @nogc
    {
        year_ = year;
        month_ = cast(ubyte) month;
    }

    static YearMonth of(int year, int month)
    {
        const validYear = validateYear(year);
        checkRange("MonthOfYear", month, 1, 12);
        return YearMonth(validYear, month);
    }

    static YearMonth of(int year, Month month)
    {
        return of(year, month.getValue());
    }

    /// Parse a year followed by a two-digit month. Retain a copy of rejected input.
    static YearMonth parse(scope const(char)[] text)
    {
        if (text is null)
            throw new NullPointerException("text");

        const parsed = readYearMonth(text);
        if (parsed.errorIndex >= 0)
            throw syntaxError(text, parsed.errorIndex, parsed.trailingText);

        try
        {
            const year = validateYear(parsed.year);
            checkRange("MonthOfYear", parsed.month, 1, 12);
            return YearMonth(year, parsed.month);
        }
        catch (DateTimeException error)
        {
            throw new DateTimeParseException("Invalid year or month", copyText(text), 0, error);
        }
    }

    int getYear() const pure nothrow @nogc
    {
        return year_;
    }

    int getMonthValue() const pure nothrow @nogc
    {
        return month_;
    }

    Month getMonth() const pure nothrow @nogc
    {
        return cast(Month)(month_ - 1);
    }

    bool isLeapYear() const pure nothrow @nogc
    {
        return isLeap(year_);
    }

    bool isValidDay(int dayOfMonth) const pure nothrow @nogc
    {
        return dayOfMonth >= 1 && dayOfMonth <= lengthOfMonth();
    }

    int lengthOfMonth() const pure nothrow @nogc
    {
        static immutable ubyte[12] lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        return month_ == 2 && isLeapYear() ? 29 : lengths[month_ - 1];
    }

    int lengthOfYear() const pure nothrow @nogc
    {
        return isLeapYear() ? 366 : 365;
    }

    YearMonth withYear(int year) const
    {
        return YearMonth(validateYear(year), month_);
    }

    YearMonth withMonth(int month) const
    {
        checkRange("MonthOfYear", month, 1, 12);
        return YearMonth(year_, month);
    }

    YearMonth plusYears(long years) const
    {
        const year = cast(long)(cast(ulong) year_ + cast(ulong) years);
        return YearMonth(validateYear(year), month_);
    }

    YearMonth plusMonths(long months) const
    {
        const current = 12L * year_ + month_ - 1;
        const total = cast(long)(cast(ulong) current + cast(ulong) months);
        const remainder = total % 12;
        const year = validateYear(total / 12 - (remainder < 0 ? 1 : 0));
        return YearMonth(year, cast(int)(remainder < 0 ? remainder + 13 : remainder + 1));
    }

    YearMonth minusYears(long years) const
    {
        return years == long.min ? plusYears(long.max).plusYears(1) : plusYears(-years);
    }

    YearMonth minusMonths(long months) const
    {
        return months == long.min ? plusMonths(long.max).plusMonths(1) : plusMonths(-months);
    }

    LocalDate atDay(int dayOfMonth) const
    {
        return LocalDate.of(year_, month_, dayOfMonth);
    }

    LocalDate atEndOfMonth() const
    {
        return atDay(lengthOfMonth());
    }

    int compareTo(YearMonth other) const pure nothrow @nogc
    {
        const years = year_ - other.year_;
        return years != 0 ? years : month_ - other.month_;
    }

    bool isBefore(YearMonth other) const pure nothrow @nogc
    {
        return compareTo(other) < 0;
    }

    bool isAfter(YearMonth other) const pure nothrow @nogc
    {
        return compareTo(other) > 0;
    }

    bool equals(YearMonth other) const pure nothrow @nogc
    {
        return year_ == other.year_ && month_ == other.month_;
    }

    int hashCode() const pure nothrow @nogc
    {
        return year_ ^ (cast(int) month_ << 27);
    }

    /// Render at least four year digits and a two-digit month.
    string toString() const pure nothrow
    {
        // Nine year digits, a possible sign and the three-byte month suffix.
        char[13] buffer = void;
        buffer[10] = '-';
        buffer[11] = cast(char)('0' + month_ / 10);
        buffer[12] = cast(char)('0' + month_ % 10);
        const start = prependYear(buffer[], 10, year_);
        return copyText(buffer[start .. $]);
    }
}

private size_t prependYear(scope char[] buffer, size_t start, int year) pure nothrow @nogc
{
    // Keep the bounded digit loop compact in the release link.
    pragma(inline, false);
    const minimumStart = start - 4;
    int magnitude = year < 0 ? -year : year;
    do
    {
        buffer[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude != 0 || start > minimumStart);
    if (year < 0)
        buffer[--start] = '-';
    return start;
}

private int validateYear(long year)
{
    checkRange("Year", year, minYear, maxYear);
    return cast(int) year;
}

private struct ParsedYearMonth
{
    long year;
    int month;
    int errorIndex;
    bool trailingText;
}

private ParsedYearMonth readYearMonth(scope const(char)[] text) pure nothrow @nogc
{
    size_t position;
    long year;
    const errorIndex = readYear(text, position, year);
    if (errorIndex >= 0)
        return ParsedYearMonth(0, 0, errorIndex);
    if (position == text.length || text[position] != '-')
        return ParsedYearMonth(0, 0, cast(int) position);

    ++position;
    if (text.length - position < 2 || !isDigit(text[position]) || !isDigit(text[position + 1]))
        return ParsedYearMonth(0, 0, cast(int) position);
    const month = 10 * (text[position] - '0') + text[position + 1] - '0';
    position += 2;
    if (position != text.length)
        return ParsedYearMonth(0, 0, cast(int) position, true);
    return ParsedYearMonth(year, month, -1);
}

// Read the signed year and leave position at the month separator.
private int readYear(scope const(char)[] text, out size_t position, out long year) pure nothrow @nogc
{
    const sign = text.length == 0 ? '\0' : text[0];
    const size_t firstDigit = sign == '+' || sign == '-' ? 1 : 0;
    position = firstDigit;
    while (position < text.length && position - firstDigit < 10 && isDigit(text[position]))
        year = 10 * year + text[position++] - '0';

    const digits = position - firstDigit;
    if (digits < 4)
        return cast(int) firstDigit;
    if ((firstDigit == 0 && digits > 4) || (sign == '+' && digits == 4) || (sign == '-' && year == 0))
        return 0;
    if (sign == '-')
        year = -year;
    return -1;
}

private bool isDigit(char c) pure nothrow @nogc
{
    return c >= '0' && c <= '9';
}

private DateTimeParseException syntaxError(scope const(char)[] text, int index, bool trailingText) pure nothrow
{
    return new DateTimeParseException(syntaxMessage(text, index, trailingText), copyText(text), index);
}

private char[] syntaxMessage(scope const(char)[] text, int index, bool trailingText) pure nothrow
{
    enum prefix = "Text '";
    const preview = errorPreview(text);
    const description = trailingText ? "' could not be parsed, unparsed text found at index "
        : "' could not be parsed at index ";

    const suffixStart = prefix.length + preview.bytes;
    const descriptionStart = suffixStart + preview.suffix.length;
    const indexStart = descriptionStart + description.length;
    // The parser inspects at most ten year digits, a sign, a separator and two month digits.
    assert(index >= 0 && index < 100);
    auto message = new char[indexStart + (index < 10 ? 1 : 2)];
    message[0 .. prefix.length] = prefix;
    message[prefix.length .. suffixStart] = text[0 .. preview.bytes];
    message[suffixStart .. descriptionStart] = preview.suffix;
    message[descriptionStart .. indexStart] = description;
    if (index >= 10)
        message[indexStart] = cast(char)('0' + index / 10);
    message[$ - 1] = cast(char)('0' + index % 10);
    return message;
}

private struct ErrorPreview
{
    size_t bytes;
    string suffix;
}

// Java limits the preview to 64 UTF-16 units. A split surrogate uses the UTF-8 replacement character.
private ErrorPreview errorPreview(scope const(char)[] text) pure nothrow @nogc
{
    enum maxUnits = 64;
    if (text.length <= maxUnits)
        return ErrorPreview(text.length);

    size_t end;
    uint units;
    while (end < text.length && units < maxUnits)
    {
        const start = end;
        const width = decodeUtf8(text, end) > 0xFFFF ? 2 : 1;
        units += width;
        if (units > maxUnits)
            return ErrorPreview(start, "\uFFFD...");
    }
    return ErrorPreview(end, end < text.length ? "..." : null);
}

// Copy borrowed text without making another object file provide the allocation template.
private char[] copyText(scope const(char)[] source) pure nothrow
{
    auto text = new char[source.length];
    text[] = source;
    return text;
}
