/// Clean-room ISO calendar periods from the Java SE 21 specification (R1, R7, R8, R11 and R14).
module flint.java.time.period;

import flint.engine.aot.text : parseLong;
import flint.java.lang : ArithmeticException, NullPointerException, NumberFormatException;
import flint.java.time.format : DateTimeParseException;

@safe:

/// A value in calendar years, months and days. Components can have different signs.
struct Period
{
    private int years_;
    private int months_;
    private int days_;

    enum Period ZERO = Period.init;

    private this(int years, int months, int days) pure nothrow @nogc
    {
        years_ = years;
        months_ = months;
        days_ = days;
    }

    static Period of(int years, int months, int days) pure nothrow @nogc
    {
        return Period(years, months, days);
    }

    static Period ofYears(int years) pure nothrow @nogc
    {
        return of(years, 0, 0);
    }

    static Period ofMonths(int months) pure nothrow @nogc
    {
        return of(0, months, 0);
    }

    static Period ofWeeks(int weeks) pure
    {
        return ofDays(checkedInt(7L * weeks));
    }

    static Period ofDays(int days) pure nothrow @nogc
    {
        return of(0, 0, days);
    }

    static Period parse(scope const(char)[] text) pure
    {
        if (text is null)
            throw new NullPointerException("text");
        const parsed = parseComponents(text);
        final switch (parsed.status)
        {
        case ParseStatus.ok:
            return parsed.value;
        case ParseStatus.dayOverflow:
            throw new ArithmeticException("integer overflow");
        case ParseStatus.componentOverflow:
            throw periodParseException(text,
                    new NumberFormatException("Period component out of integer range"));
        case ParseStatus.signOverflow:
            throw periodParseException(text, new ArithmeticException("integer overflow"));
        case ParseStatus.syntax:
            throw periodParseException(text, null);
        }
    }

    int getYears() const pure nothrow @nogc
    {
        return years_;
    }

    int getMonths() const pure nothrow @nogc
    {
        return months_;
    }

    int getDays() const pure nothrow @nogc
    {
        return days_;
    }

    bool isZero() const pure nothrow @nogc
    {
        return years_ == 0 && months_ == 0 && days_ == 0;
    }

    bool isNegative() const pure nothrow @nogc
    {
        return years_ < 0 || months_ < 0 || days_ < 0;
    }

    Period withYears(int years) const pure nothrow @nogc
    {
        return of(years, months_, days_);
    }

    Period withMonths(int months) const pure nothrow @nogc
    {
        return of(years_, months, days_);
    }

    Period withDays(int days) const pure nothrow @nogc
    {
        return of(years_, months_, days);
    }

    Period plus(Period amount) const pure
    {
        return of(checkedInt(cast(long) years_ + amount.years_),
                checkedInt(cast(long) months_ + amount.months_), checkedInt(cast(long) days_ + amount.days_));
    }

    Period plusYears(long years) const pure
    {
        return withYears(addComponent(years_, years));
    }

    Period plusMonths(long months) const pure
    {
        return withMonths(addComponent(months_, months));
    }

    Period plusDays(long days) const pure
    {
        return withDays(addComponent(days_, days));
    }

    Period minus(Period amount) const pure
    {
        return of(checkedInt(cast(long) years_ - amount.years_),
                checkedInt(cast(long) months_ - amount.months_), checkedInt(cast(long) days_ - amount.days_));
    }

    Period minusYears(long years) const pure
    {
        return withYears(subtractComponent(years_, years));
    }

    Period minusMonths(long months) const pure
    {
        return withMonths(subtractComponent(months_, months));
    }

    Period minusDays(long days) const pure
    {
        return withDays(subtractComponent(days_, days));
    }

    Period multipliedBy(int scalar) const pure
    {
        return of(checkedInt(cast(long) years_ * scalar), checkedInt(cast(long) months_ * scalar),
                checkedInt(cast(long) days_ * scalar));
    }

    Period negated() const pure
    {
        return multipliedBy(-1);
    }

    Period normalized() const pure
    {
        const total = toTotalMonths();
        return of(checkedInt(total / 12), cast(int)(total % 12), days_);
    }

    long toTotalMonths() const pure nothrow @nogc
    {
        return 12L * years_ + months_;
    }

    bool equals(Period other) const pure nothrow @nogc
    {
        return this == other;
    }

    int hashCode() const pure nothrow @nogc
    {
        const months = cast(uint) months_;
        const days = cast(uint) days_;
        return years_ + cast(int)((months << 8) | (months >> 24)) + cast(int)((days << 16) | (days >> 16));
    }

    /// Emit only non-zero components, using `P0D` for the zero period.
    string toString() const pure nothrow
    {
        if (isZero())
            return "P0D";
        // Each signed int needs at most 11 characters, plus its unit suffix.
        char[37] buffer;
        size_t start = buffer.length;
        prependComponent(buffer, start, days_, 'D');
        prependComponent(buffer, start, months_, 'M');
        prependComponent(buffer, start, years_, 'Y');
        buffer[--start] = 'P';
        return buffer[start .. $].idup;
    }
}

private bool fitsInt(long value) pure nothrow @nogc
{
    return value >= int.min && value <= int.max;
}

private int checkedInt(long value) pure
{
    if (!fitsInt(value))
        throw new ArithmeticException("integer overflow");
    return cast(int) value;
}

private int addComponent(int component, long delta) pure
{
    if (delta < int.min - cast(long) component || delta > int.max - cast(long) component)
        throw new ArithmeticException("integer overflow");
    return cast(int)(component + delta);
}

private int subtractComponent(int component, long delta) pure
{
    if (delta < cast(long) component - int.max || delta > cast(long) component - int.min)
        throw new ArithmeticException("integer overflow");
    return cast(int)(component - delta);
}

private void prependComponent(ref scope char[37] buffer, ref size_t start, int value, char unit) pure nothrow @nogc
{
    if (value == 0)
        return;
    buffer[--start] = unit;
    long magnitude = value < 0 ? -cast(long) value : value;
    do
    {
        buffer[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude != 0);
    if (value < 0)
        buffer[--start] = '-';
}

private DateTimeParseException periodParseException(scope const(char)[] text, Throwable cause) pure nothrow
{
    return new DateTimeParseException("Text cannot be parsed to a Period", text.idup, 0, cause);
}

private enum ParseStatus
{
    syntax,
    componentOverflow,
    signOverflow,
    dayOverflow,
    ok,
}

private struct ParsedPeriod
{
    ParseStatus status;
    Period value;
}

private struct ComponentSpan
{
    size_t start;
    size_t end;
}

private ParsedPeriod parseComponents(scope const(char)[] text) pure nothrow @nogc
{
    if (text.length == 0)
        return ParsedPeriod.init;
    const sign = text[0] == '-' ? -1 : 1;
    const size_t prefix = text[0] == '-' || text[0] == '+' ? 1 : 0;
    if (text.length <= prefix + 1 || (text[prefix] | 0x20) != 'p')
        return ParsedPeriod.init;
    return readComponents(text, prefix + 1, sign);
}

private ParsedPeriod readComponents(scope const(char)[] text, size_t start, int sign) pure nothrow @nogc
{
    ComponentSpan[4] spans;
    if (!scanComponents(text, start, spans))
        return ParsedPeriod.init;
    long[4] values;
    foreach (i, span; spans)
    {
        if (span.end == 0)
            continue;
        long value;
        if (!parseLong(text[span.start .. span.end], value) || !fitsInt(value))
            return ParsedPeriod(ParseStatus.componentOverflow);
        if (!fitsInt(value * sign))
            return ParsedPeriod(ParseStatus.signOverflow);
        values[i] = value * sign;
    }

    const weeksInDays = 7 * values[2];
    const days = weeksInDays + values[3];
    if (!fitsInt(weeksInDays) || !fitsInt(days))
        return ParsedPeriod(ParseStatus.dayOverflow);
    return ParsedPeriod(ParseStatus.ok, Period.of(cast(int) values[0], cast(int) values[1], cast(int) days));
}

// Record each numeric token so the complete syntax is checked before converting any of its numbers.
private bool scanComponents(scope const(char)[] text, size_t index, ref scope ComponentSpan[4] spans) pure nothrow @nogc
{
    enum units = "ymwd";
    size_t nextUnit;
    while (index < text.length)
    {
        const end = endOfNumber(text, index);
        if (end == index || end == text.length)
            return false;
        const unit = text[end] | 0x20; // ASCII lower-case units.
        while (nextUnit < units.length && units[nextUnit] != unit)
            ++nextUnit;
        if (nextUnit == units.length)
            return false;
        spans[nextUnit++] = ComponentSpan(index, end);
        index = end + 1;
    }
    return true;
}

private size_t endOfNumber(scope const(char)[] text, size_t start) pure nothrow @nogc
{
    size_t index = start;
    if (text[index] == '-' || text[index] == '+')
        ++index;
    const digits = index;
    while (index < text.length && text[index] >= '0' && text[index] <= '9')
        ++index;
    return index == digits ? start : index;
}
