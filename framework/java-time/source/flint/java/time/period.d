/*
 * Copyright (c) 1994, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

// Modified by the Flint authors.
// Component bounds checking adapted from OpenJDK jdk-21.0.13-ga
// src/java.base/share/classes/java/lang/Integer.java (parseInt(CharSequence, int, int, int)).

/// ISO calendar periods from the Java SE 21 API (R1, R7, R8, R11 and R14).
module flint.java.time.period;

import flint.engine.aot.text : parseLong;
import flint.java.lang : ArithmeticException, NumberFormatException;
import flint.java.time : LocalDate, epochDayOf;
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

    /// The directed ISO calendar difference from the start date to the exclusive end date.
    static Period between(LocalDate startDateInclusive, LocalDate endDateExclusive) pure nothrow @nogc
    {
        const endMonth = endDateExclusive.getMonthValue();
        const startDay = startDateInclusive.getDayOfMonth();
        const endDay = endDateExclusive.getDayOfMonth();
        const yearDifference = endDateExclusive.getYear() - startDateInclusive.getYear();
        long months = 12L * yearDifference + endMonth - startDateInclusive.getMonthValue();
        int days = endDay - startDay;
        if (months > 0 && days < 0)
        {
            // Stop in the previous month, clipping the start day to its length.
            --months;
            const previousYear = endDateExclusive.getYear() - (endMonth == 1 ? 1 : 0);
            const previousMonth = endMonth == 1 ? 12 : endMonth - 1;
            const firstOfEndMonth = endDateExclusive.toEpochDay() - endDay + 1;
            const previousLength = cast(int)(firstOfEndMonth - epochDayOf(previousYear, previousMonth, 1));
            days = endDay + (previousLength > startDay ? previousLength - startDay : 0);
        }
        else if (months < 0 && days > 0)
        {
            ++months;
            days -= endDateExclusive.lengthOfMonth();
        }
        return of(cast(int)(months / 12), cast(int)(months % 12), days);
    }

    static Period parse(scope const(char)[] text) pure
    {
        const parsed = parseComponents(text);
        final switch (parsed.status)
        {
        case ParseStatus.ok:
            return parsed.value;
        case ParseStatus.dayOverflow:
            throw new ArithmeticException("integer overflow");
        case ParseStatus.componentOverflow:
            const component = text[parsed.rejected.start .. parsed.rejected.end];
            throw periodParseException(text, new NumberFormatException(overflowMessage(component)));
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
        return copyText(buffer[start .. $]);
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
    const magnitude = value < 0 ? -cast(long) value : value;
    start = prependDigits(buffer[], start, cast(ulong) magnitude);
    if (value < 0)
        buffer[--start] = '-';
}

private size_t prependDigits(scope char[] buffer, size_t start, ulong magnitude) pure nothrow @nogc
{
    // Keep the digit loop shared under the optimized link profiles.
    pragma(inline, false);
    do
    {
        buffer[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude != 0);
    return start;
}

private DateTimeParseException periodParseException(scope const(char)[] text, Throwable cause) pure nothrow
{
    return new DateTimeParseException("Text cannot be parsed to a Period", copyText(text), 0, cause);
}

private char[] overflowMessage(scope const(char)[] component) pure nothrow
{
    enum prefix = "Error at index ";
    enum separator = " in: \"";
    char[20] digits;
    const start = prependDigits(digits[], digits.length, firstOverflowingDigit(component));

    const separatorStart = prefix.length + digits.length - start;
    const componentStart = separatorStart + separator.length;
    auto message = new char[componentStart + component.length + 1];
    message[0 .. prefix.length] = prefix;
    message[prefix.length .. separatorStart] = digits[start .. $];
    message[separatorStart .. componentStart] = separator;
    message[componentStart .. $ - 1] = component;
    message[$ - 1] = '"';
    return message;
}

// Keep Period's text allocation in this archive member.
private char[] copyText(scope const(char)[] source) pure nothrow
{
    auto text = new char[source.length];
    text[] = source;
    return text;
}

private enum ParseStatus
{
    syntax,
    componentOverflow,
    signOverflow,
    dayOverflow,
    ok,
}

private struct ComponentSpan
{
    size_t start;
    size_t end;
}

private struct ParsedPeriod
{
    ParseStatus status;
    Period value;
    ComponentSpan rejected;
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
            return ParsedPeriod(ParseStatus.componentOverflow, Period.ZERO, span);
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

/// Locate the first overflowing digit in a rejected token whose syntax was checked by scanComponents.
private size_t firstOverflowingDigit(scope const(char)[] token) pure nothrow @nogc
{
    const negative = token[0] == '-';
    size_t index = negative || token[0] == '+' ? 1 : 0;
    const limit = negative ? int.min : -int.max;
    const multiplyMinimum = limit / 10;
    int result;
    for (; index < token.length; ++index)
    {
        const digit = token[index] - '0';
        if (result < multiplyMinimum)
            return index;
        result *= 10;
        if (result < limit + digit)
            return index;
        result -= digit;
    }
    return index;
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
