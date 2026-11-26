/*
 * Copyright (c) 2012, 2020, Oracle and/or its affiliates. All rights reserved.
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

/*
 * This file is available under and governed by the GNU General Public
 * License version 2 only, as published by the Free Software Foundation.
 * However, the following notice accompanied the original version of this
 * file:
 *
 * Copyright (c) 2009-2012, Stephen Colebourne & Michael Nascimento Santos
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 *  * Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 *  * Neither the name of JSR-310 nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/time/zone/ZoneOffsetTransitionRule.java
// Modified by the Flint authors.
module flint.java.time.zone.zoneoffsettransitionrule;

import flint.java.lang : IllegalArgumentException;
import flint.java.time : DayOfWeek, LocalDate, LocalDateTime, LocalTime, Month, ZoneOffset;
import std.typecons : Nullable;

@safe:

/// A recurring yearly rule. The default is a gap at the start of January 1.
struct ZoneOffsetTransitionRule
{
    /// The time scale used by the rule.
    enum TimeDefinition
    {
        UTC,
        WALL,
        STANDARD,
    }

    private Month month_;
    private byte day_ = 1;
    private byte weekday_ = -1;
    private LocalTime time_;
    private bool endOfDay_;
    private TimeDefinition definition_ = TimeDefinition.WALL;
    private ZoneOffset standard_;
    private ZoneOffset before_;
    private ZoneOffset after_ = ZoneOffset.ofHours(1);

    private this(Month month, byte day, byte weekday, LocalTime time, bool endOfDay,
            TimeDefinition definition, ZoneOffset standard, ZoneOffset before, ZoneOffset after) pure nothrow @nogc
    {
        month_ = month;
        day_ = day;
        weekday_ = weekday;
        time_ = time;
        endOfDay_ = endOfDay;
        definition_ = definition;
        standard_ = standard;
        before_ = before;
        after_ = after;
    }

    static pure ZoneOffsetTransitionRule of(Month month, int dayOfMonthIndicator, DayOfWeek dayOfWeek,
            LocalTime time, bool timeEndOfDay,
            TimeDefinition timeDefinition, ZoneOffset standardOffset, ZoneOffset offsetBefore, ZoneOffset offsetAfter)
    {
        if (cast(uint) dayOfWeek > DayOfWeek.SUNDAY)
            throw new IllegalArgumentException("Invalid day of week");
        return checkedRule(month, dayOfMonthIndicator, dayOfWeek, time, timeEndOfDay,
                timeDefinition, standardOffset, offsetBefore, offsetAfter);
    }

    static pure ZoneOffsetTransitionRule of()(Month month, int dayOfMonthIndicator,
            Nullable!DayOfWeek dayOfWeek, LocalTime time, bool timeEndOfDay,
            TimeDefinition timeDefinition, ZoneOffset standardOffset, ZoneOffset offsetBefore, ZoneOffset offsetAfter)
    {
        return dayOfWeek.isNull ? checkedRule(month, dayOfMonthIndicator, -1, time, timeEndOfDay,
                timeDefinition, standardOffset, offsetBefore, offsetAfter) : of(month, dayOfMonthIndicator,
                dayOfWeek.get(), time, timeEndOfDay, timeDefinition, standardOffset, offsetBefore, offsetAfter);
    }

    private static ZoneOffsetTransitionRule checkedRule(Month month, int day, int weekday, LocalTime time,
            bool endOfDay, TimeDefinition definition, ZoneOffset standard, ZoneOffset before, ZoneOffset after) pure
    {
        if (day < -28 || day > 31 || day == 0)
            throw new IllegalArgumentException(
                    "Day of month indicator must be between -28 and 31 inclusive excluding zero");
        if (endOfDay && time != LocalTime.MIDNIGHT)
            throw new IllegalArgumentException("Time must be midnight when end of day flag is true");
        if (time.getNano() != 0)
            throw new IllegalArgumentException("Time's nano-of-second must be zero");
        if (cast(uint) month > Month.DECEMBER)
            throw new IllegalArgumentException("Invalid month");
        if (cast(uint) definition > TimeDefinition.STANDARD)
            throw new IllegalArgumentException("Invalid time definition");
        return ZoneOffsetTransitionRule(month, cast(byte) day, cast(byte) weekday, time, endOfDay,
                definition, standard, before, after);
    }

    Month getMonth() const pure nothrow @nogc
    {
        return month_;
    }

    int getDayOfMonthIndicator() const pure nothrow @nogc
    {
        return day_;
    }

    // Instantiate the nullable result in the caller.
    Nullable!DayOfWeek getDayOfWeek()() const pure nothrow @nogc
    {
        return weekday_ < 0 ? Nullable!DayOfWeek.init : Nullable!DayOfWeek(cast(DayOfWeek) weekday_);
    }

    LocalTime getLocalTime() const pure nothrow @nogc
    {
        return time_;
    }

    bool isMidnightEndOfDay() const pure nothrow @nogc
    {
        return endOfDay_;
    }

    TimeDefinition getTimeDefinition() const pure nothrow @nogc
    {
        return definition_;
    }

    ZoneOffset getStandardOffset() const pure nothrow @nogc
    {
        return standard_;
    }

    ZoneOffset getOffsetBefore() const pure nothrow @nogc
    {
        return before_;
    }

    ZoneOffset getOffsetAfter() const pure nothrow @nogc
    {
        return after_;
    }

    /// Compute the rule's transition in the specified year.
    auto createTransition()(int year) const
    {
        import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;

        return ZoneOffsetTransition(wallTime(year), before_, after_);
    }

    private LocalDateTime wallTime(int year) const
    {
        LocalDate date;
        if (day_ < 0)
        {
            const first = LocalDate.of(year, month_, 1);
            date = first.plusDays(first.lengthOfMonth() + day_);
        }
        else
            date = LocalDate.of(year, month_, day_);

        if (weekday_ >= 0)
        {
            const current = cast(int) date.getDayOfWeek();
            const shift = day_ < 0 ? -((current - weekday_ + 7) % 7) : (weekday_ - current + 7) % 7;
            date = date.plusDays(shift);
        }
        if (endOfDay_)
            date = date.plusDays(1);

        return definition_.createDateTime(LocalDateTime.of(date, time_), standard_, before_);
    }

    bool equals(ZoneOffsetTransitionRule other) const pure nothrow @nogc
    {
        return month_ == other.month_ && day_ == other.day_ && weekday_ == other.weekday_
            && time_ == other.time_ && endOfDay_ == other.endOfDay_ && definition_ == other.definition_
            && standard_ == other.standard_ && before_ == other.before_ && after_ == other.after_;
    }

    int hashCode() const pure nothrow @nogc
    {
        const weekday = weekday_ < 0 ? 7 : weekday_;
        const hash = ((time_.toSecondOfDay() + (endOfDay_ ? 1 : 0)) << 15) + (
                cast(int) month_ << 11) + ((day_ + 32) << 5) + (weekday << 2) + cast(int) definition_;
        return hash ^ standard_.getTotalSeconds() ^ before_.getTotalSeconds() ^ after_.getTotalSeconds();
    }

    string toString() const pure nothrow
    {
        // Even the longest weekday/month form with three second-precision offsets fits in 160 bytes.
        char[160] text = void;
        size_t end;
        append(text[], end, before_.compareTo(after_) > 0 ? "TransitionRule[Gap " : "TransitionRule[Overlap ");
        append(text[], end, before_.getId());
        append(text[], end, " to ");
        append(text[], end, after_.getId());
        append(text[], end, ", ");
        const month = monthNames[month_];
        if (weekday_ >= 0)
        {
            append(text[], end, weekdayNames[weekday_]);
            if (day_ == -1)
                append(text[], end, " on or before last day of ");
            else if (day_ < 0)
            {
                append(text[], end, " on or before last day minus ");
                appendDay(text[], end, -day_ - 1);
                append(text[], end, " of ");
            }
            else
                append(text[], end, " on or after ");
        }
        append(text[], end, month);
        if (weekday_ < 0 || day_ > 0)
        {
            append(text[], end, " ");
            appendDay(text[], end, day_);
        }
        append(text[], end, " at ");
        append(text[], end, endOfDay_ ? "24:00" : time_.toString());
        append(text[], end, " ");
        append(text[], end, definitionNames[definition_]);
        append(text[], end, ", standard offset ");
        append(text[], end, standard_.getId());
        append(text[], end, "]");

        auto result = new char[end];
        result[] = text[0 .. end];
        return result;
    }
}

/// Convert a rule's date-time to the wall time in the before offset.
LocalDateTime createDateTime(ZoneOffsetTransitionRule.TimeDefinition definition,
        LocalDateTime dateTime, ZoneOffset standardOffset, ZoneOffset wallOffset)
{
    alias TimeDefinition = ZoneOffsetTransitionRule.TimeDefinition;
    final switch (definition)
    {
    case TimeDefinition.UTC:
        return dateTime.plusSeconds(wallOffset.getTotalSeconds());
    case TimeDefinition.WALL:
        return dateTime;
    case TimeDefinition.STANDARD:
        return dateTime.plusSeconds(wallOffset.getTotalSeconds() - standardOffset.getTotalSeconds());
    }
}

/// Return a fresh array of the time definitions in declaration order.
ZoneOffsetTransitionRule.TimeDefinition[] values() pure nothrow
{
    alias TimeDefinition = ZoneOffsetTransitionRule.TimeDefinition;
    auto definitions = new TimeDefinition[definitionNames.length];
    foreach (index, ref definition; definitions)
        definition = cast(TimeDefinition) index;
    return definitions;
}

/// Resolve the exact declared Java enum name.
ZoneOffsetTransitionRule.TimeDefinition valueOf(scope const(char)[] spelling) pure
{
    foreach (index, name; definitionNames)
    {
        if (name == spelling)
            return cast(ZoneOffsetTransitionRule.TimeDefinition) index;
    }
    throw new IllegalArgumentException(unknownDefinitionMessage(spelling));
}

private string unknownDefinitionMessage(scope const(char)[] spelling) pure nothrow
{
    enum prefix = "No enum constant java.time.zone.ZoneOffsetTransitionRule.TimeDefinition.";
    auto message = new char[prefix.length + spelling.length];
    message[0 .. prefix.length] = prefix[];
    message[prefix.length .. $] = spelling;
    return message;
}

private immutable string[12] monthNames = [
    "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER",
    "OCTOBER", "NOVEMBER", "DECEMBER"
];
private immutable string[7] weekdayNames = [
    "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"
];
private immutable string[3] definitionNames = ["UTC", "WALL", "STANDARD"];

private void append(scope char[] output, ref size_t end, scope const(char)[] value) pure nothrow @nogc
{
    pragma(inline, false);
    output[end .. end + value.length] = value[];
    end += value.length;
}

private void appendDay(scope char[] output, ref size_t end, int day) pure nothrow @nogc
{
    if (day < 0)
    {
        output[end++] = '-';
        day = -day;
    }
    if (day >= 10)
        output[end++] = cast(char)('0' + day / 10);
    output[end++] = cast(char)('0' + day % 10);
}
