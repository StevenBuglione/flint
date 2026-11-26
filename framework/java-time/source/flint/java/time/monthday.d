/// Clean-room Java SE 21 ISO month and day values.
module flint.java.time.monthday;

import flint.java.time : DateTimeException, LocalDate, Month, getValue, isLeap;
import flint.java.time.format : DateTimeParseException;

@safe:

/// A month and day independent of the year. The D default is January 1.
struct MonthDay
{
    private ubyte month_ = 1;
    private ubyte day_ = 1;

    private this(int month, int dayOfMonth) pure nothrow @nogc
    {
        month_ = cast(ubyte) month;
        day_ = cast(ubyte) dayOfMonth;
    }

    static MonthDay of(int month, int dayOfMonth)
    {
        const valid = LocalDate.of(2000, month, dayOfMonth);
        return MonthDay(valid.getMonthValue(), valid.getDayOfMonth());
    }

    static MonthDay of(Month month, int dayOfMonth)
    {
        return of(month.getValue(), dayOfMonth);
    }

    static MonthDay parse(scope const(char)[] text)
    {
        if (text.length < 2 || text[0] != '-' || text[1] != '-')
            throw parseError(text, 0);
        const month = readPair(text[2 .. $]);
        if (month < 0)
            throw parseError(text, 2);
        if (text.length == 4 || text[4] != '-')
            throw parseError(text, 4);
        const dayOfMonth = readPair(text[5 .. $]);
        if (dayOfMonth < 0)
            throw parseError(text, 5);
        if (text.length != 7)
            throw parseError(text, 7);
        try
        {
            return of(month, dayOfMonth);
        }
        catch (DateTimeException error)
        {
            throw parseError(text, 0, error);
        }
    }

    int getMonthValue() const pure nothrow @nogc
    {
        return month_;
    }

    Month getMonth() const pure nothrow @nogc
    {
        return cast(Month)(month_ - 1);
    }

    int getDayOfMonth() const pure nothrow @nogc
    {
        return day_;
    }

    bool isValidYear(int year) const pure nothrow @nogc
    {
        return month_ != 2 || day_ != 29 || isLeap(year);
    }

    MonthDay withMonth(int month) const
    {
        const first = LocalDate.of(2000, month, 1);
        const maxDay = first.lengthOfMonth();
        return MonthDay(month, day_ <= maxDay ? day_ : maxDay);
    }

    MonthDay with_(Month month) const
    {
        return withMonth(month.getValue());
    }

    MonthDay withDayOfMonth(int dayOfMonth) const
    {
        return of(month_, dayOfMonth);
    }

    LocalDate atYear(int year) const
    {
        return LocalDate.of(year, month_, isValidYear(year) ? day_ : 28);
    }

    int compareTo(MonthDay other) const pure nothrow @nogc
    {
        const months = month_ - other.month_;
        return months != 0 ? months : day_ - other.day_;
    }

    bool isAfter(MonthDay other) const pure nothrow @nogc
    {
        return compareTo(other) > 0;
    }

    bool isBefore(MonthDay other) const pure nothrow @nogc
    {
        return compareTo(other) < 0;
    }

    bool equals(MonthDay other) const pure nothrow @nogc
    {
        return month_ == other.month_ && day_ == other.day_;
    }

    int hashCode() const pure nothrow @nogc
    {
        return (cast(int) month_ << 6) + day_;
    }

    string toString() const pure nothrow
    {
        char[7] text = [
            '-', '-', cast(char)('0' + month_ / 10), cast(char)('0' + month_ % 10), '-',
            cast(char)('0' + day_ / 10), cast(char)('0' + day_ % 10)
        ];
        return copyText(text[]);
    }
}

private int readPair(scope const(char)[] text) pure nothrow @nogc
{
    if (text.length < 2)
        return -1;
    const first = cast(uint)(text[0] - '0');
    const second = cast(uint)(text[1] - '0');
    return first <= 9 && second <= 9 ? cast(int)(10 * first + second) : -1;
}

private DateTimeParseException parseError(scope const(char)[] text, int index, Throwable cause = null) pure nothrow
{
    return new DateTimeParseException("Text cannot be parsed to a MonthDay", copyText(text), index, cause);
}

private char[] copyText(scope const(char)[] source) pure nothrow
{
    auto text = new char[source.length];
    text[] = source;
    return text;
}
