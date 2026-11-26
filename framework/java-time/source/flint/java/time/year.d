/// Clean-room Java SE 21 ISO calendar years.
module flint.java.time.year;

import flint.engine.aot.text : decimal;
import flint.java.lang : NullPointerException;
import flint.java.time : LocalDate, Month, checkRange, isIsoLeap = isLeap;
import flint.java.time.format : DateTimeParseException;
public import flint.java.time.monthday : MonthDay;
import flint.java.time.yearmonth : YearMonth;
import std.typecons : Nullable;

@safe:

/// A proleptic Gregorian calendar year. The D default is 1970.
struct Year
{
    enum MIN_VALUE = -999_999_999;
    enum MAX_VALUE = 999_999_999;

    private int value_ = 1970;

    private this(int value) pure nothrow @nogc
    {
        value_ = value;
    }

    static Year of(int year)
    {
        return checkedYear(year);
    }

    static Year parse(scope const(char)[] text)
    {
        if (text is null)
            throw new NullPointerException("text");
        const sign = text.length == 0 ? '\0' : text[0];
        const size_t firstDigit = sign == '-' || sign == '+' ? 1 : 0;
        size_t position = firstDigit;
        int value;
        while (position < text.length && position - firstDigit < 9)
        {
            const digit = cast(uint)(text[position] - '0');
            if (digit > 9)
                break;
            value = 10 * value + cast(int) digit;
            ++position;
        }
        if (position == firstDigit || position != text.length)
            throw new DateTimeParseException("Text cannot be parsed to a Year", copyText(text), cast(int) position);
        return Year(sign == '-' ? -value : value);
    }

    static bool isLeap(long year) pure nothrow @nogc
    {
        return isIsoLeap(year);
    }

    int getValue() const pure nothrow @nogc
    {
        return value_;
    }

    bool isLeap() const pure nothrow @nogc
    {
        return isIsoLeap(value_);
    }

    // The composition methods link MonthDay or YearMonth only when called.
    bool isValidMonthDay()(MonthDay monthDay) const pure nothrow @nogc
    {
        return monthDay.isValidYear(value_);
    }

    bool isValidMonthDay()(Nullable!MonthDay monthDay) const pure nothrow @nogc
    {
        return !monthDay.isNull && isValidMonthDay(monthDay.get());
    }

    int length() const pure nothrow @nogc
    {
        return isLeap() ? 366 : 365;
    }

    Year plusYears(long years) const
    {
        const value = cast(long)(cast(ulong) value_ + cast(ulong) years);
        return checkedYear(value);
    }

    Year minusYears(long years) const
    {
        return years == long.min ? plusYears(long.max).plusYears(1) : plusYears(-years);
    }

    LocalDate atDay(int dayOfYear) const
    {
        return LocalDate.ofYearDay(value_, dayOfYear);
    }

    YearMonth atMonth()(int month) const
    {
        return YearMonth.of(value_, month);
    }

    YearMonth atMonth()(Month month) const
    {
        return YearMonth.of(value_, month);
    }

    LocalDate atMonthDay()(MonthDay monthDay) const
    {
        return monthDay.atYear(value_);
    }

    int compareTo(Year other) const pure nothrow @nogc
    {
        return value_ - other.value_;
    }

    bool isAfter(Year other) const pure nothrow @nogc
    {
        return value_ > other.value_;
    }

    bool isBefore(Year other) const pure nothrow @nogc
    {
        return value_ < other.value_;
    }

    bool equals(Year other) const pure nothrow @nogc
    {
        return value_ == other.value_;
    }

    int hashCode() const pure nothrow @nogc
    {
        return value_;
    }

    string toString() const pure nothrow
    {
        return decimal(value_);
    }

    private static Year checkedYear(long year)
    {
        checkRange("Year", year, MIN_VALUE, MAX_VALUE);
        return Year(cast(int) year);
    }
}

private char[] copyText(scope const(char)[] source) pure nothrow
{
    auto text = new char[source.length];
    text[] = source;
    return text;
}
