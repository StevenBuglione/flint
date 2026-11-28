/*
 * Copyright (c) 2009, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/file/attribute/FileTime.java
// Modified by the Flint authors: a value type (struct), lazy caches dropped, and Java's
// Comparable/Object contract mapped to equals/hashCode/compareTo/opCmp.

module flint.java.nio.file.attribute.filetime;

import flint.java.time : Instant, LocalDateTime, ZoneOffset;
import flint.java.util.concurrent : TimeUnit, convert, toDays, toMillis, toNanos, toSeconds;

@safe:

/// Represents the value of a file's time stamp attribute, such as a last-modified, last-access or creation time.
struct FileTime
{
    // The unit and value pair, valid when `hasUnit_`; otherwise `instant_` carries the time.
    private TimeUnit unit_;
    private long value_;
    private bool hasUnit_;
    private Instant instant_;

    private enum long hoursPerDay = 24L;
    private enum long minutesPerHour = 60L;
    private enum long secondsPerMinute = 60L;
    private enum long secondsPerHour = secondsPerMinute * minutesPerHour;
    private enum long secondsPerDay = secondsPerHour * hoursPerDay;
    private enum long millisPerSecond = 1_000L;
    private enum long microsPerSecond = 1000_000L;
    private enum long nanosPerSecond = 1000_000_000L;
    private enum int nanosPerMilli = 1000_000;
    private enum int nanosPerMicro = 1000;
    // The epoch second of Instant.MIN.
    private enum long minSecond = -31_557_014_167_219_200L;
    // The epoch second of Instant.MAX.
    private enum long maxSecond = 31_556_889_864_403_199L;

    private static FileTime fromUnit(long value, TimeUnit unit) pure nothrow @nogc
    {
        FileTime result;
        result.value_ = value;
        result.unit_ = unit;
        result.hasUnit_ = true;
        return result;
    }

    private static FileTime fromInstantValue(Instant instant) pure nothrow @nogc
    {
        FileTime result;
        result.instant_ = instant;
        result.hasUnit_ = false;
        return result;
    }

    /// Returns a `FileTime` at the given unit of granularity since the epoch.
    static FileTime from(long value, TimeUnit unit) pure nothrow @nogc
    {
        return fromUnit(value, unit);
    }

    /// Returns a `FileTime` representing the given value in milliseconds since the epoch.
    static FileTime fromMillis(long value) pure nothrow @nogc
    {
        return fromUnit(value, TimeUnit.MILLISECONDS);
    }

    /// Returns a `FileTime` representing the same point on the time-line as `instant`.
    static FileTime from(Instant instant) pure nothrow @nogc
    {
        return fromInstantValue(instant);
    }

    /// Returns the value at the given unit of granularity, saturating on overflow.
    long to(TimeUnit unit) const pure nothrow @nogc
    {
        if (hasUnit_)
            return unit.convert(value_, unit_);
        const secs = unit.convert(instant_.getEpochSecond(), TimeUnit.SECONDS);
        if (secs == long.min || secs == long.max)
            return secs;
        const nanos = unit.convert(instant_.getNano(), TimeUnit.NANOSECONDS);
        const r = secs + nanos;
        if (((secs ^ r) & (nanos ^ r)) < 0)
            return secs < 0 ? long.min : long.max;
        return r;
    }

    /// Returns the value in milliseconds since the epoch, saturating on overflow.
    long toMillis() const pure nothrow @nogc
    {
        if (hasUnit_)
            return unit_.toMillis(value_);
        const secs = instant_.getEpochSecond();
        const nanos = instant_.getNano();
        const r = secs * 1000;
        const ax = secs < 0 ? -secs : secs;
        if ((cast(ulong)(ax | 1000) >>> 31) != 0 && r / 1000 != secs)
            return secs < 0 ? long.min : long.max;
        return r + nanos / nanosPerMilli;
    }

    private static long scale(long d, long m, long over) pure nothrow @nogc
    {
        if (d > over)
            return long.max;
        if (d < -over)
            return long.min;
        return d * m;
    }

    /// Returns the instant that represents the same point on the time-line, saturating at `Instant.MIN` and `Instant.MAX`.
    Instant toInstant() const pure nothrow @nogc
    {
        if (!hasUnit_)
            return instant_;
        long secs = 0L;
        int nanos = 0;
        final switch (unit_)
        {
        case TimeUnit.DAYS:
            secs = scale(value_, secondsPerDay, long.max / secondsPerDay);
            break;
        case TimeUnit.HOURS:
            secs = scale(value_, secondsPerHour, long.max / secondsPerHour);
            break;
        case TimeUnit.MINUTES:
            secs = scale(value_, secondsPerMinute, long.max / secondsPerMinute);
            break;
        case TimeUnit.SECONDS:
            secs = value_;
            break;
        case TimeUnit.MILLISECONDS:
            secs = floorDiv(value_, millisPerSecond);
            nanos = cast(int) floorMod(value_, millisPerSecond) * nanosPerMilli;
            break;
        case TimeUnit.MICROSECONDS:
            secs = floorDiv(value_, microsPerSecond);
            nanos = cast(int) floorMod(value_, microsPerSecond) * nanosPerMicro;
            break;
        case TimeUnit.NANOSECONDS:
            secs = floorDiv(value_, nanosPerSecond);
            nanos = cast(int) floorMod(value_, nanosPerSecond);
            break;
        }
        if (secs <= minSecond)
            return Instant.ofEpochSecond(minSecond, 0);
        if (secs >= maxSecond)
            return Instant.ofEpochSecond(maxSecond, 999_999_999);
        return Instant.ofEpochSecond(secs, nanos);
    }

    /// Whether this file time equals `other`, comparing the same point on the time-line.
    bool equals(FileTime other) const pure nothrow @nogc
    {
        return compareTo(other) == 0;
    }

    /// Whether this file time equals `other` (Java's `Object.equals`).
    bool opEquals(const FileTime other) const pure nothrow @nogc
    {
        return compareTo(other) == 0;
    }

    /// Java's `hashCode`, based on the instant representation.
    int hashCode() const pure nothrow @nogc
    {
        return toInstant().hashCode();
    }

    /// The hash for an associative array key.
    size_t toHash() const pure nothrow @nogc
    {
        return cast(size_t) cast(uint) hashCode();
    }

    private long toDays() const pure nothrow @nogc
    {
        if (hasUnit_)
            return unit_.toDays(value_);
        return TimeUnit.SECONDS.toDays(toInstant().getEpochSecond());
    }

    private long toExcessNanos(long days) const pure nothrow @nogc
    {
        if (hasUnit_)
            return unit_.toNanos(value_ - unit_.convert(days, TimeUnit.DAYS));
        return TimeUnit.SECONDS.toNanos(toInstant().getEpochSecond() - TimeUnit.DAYS.toSeconds(days));
    }

    /// Compares this file time to `other`: negative, zero or positive.
    int compareTo(FileTime other) const pure nothrow @nogc
    {
        if (hasUnit_ && other.hasUnit_ && unit_ == other.unit_)
            return compareLong(value_, other.value_);
        const secs = toInstant().getEpochSecond();
        const secsOther = other.toInstant().getEpochSecond();
        int cmp = compareLong(secs, secsOther);
        if (cmp != 0)
            return cmp;
        cmp = compareLong(toInstant().getNano(), other.toInstant().getNano());
        if (cmp != 0)
            return cmp;
        if (secs != maxSecond && secs != minSecond)
            return 0;
        const days = toDays();
        const daysOther = other.toDays();
        if (days == daysOther)
            return compareLong(toExcessNanos(days), other.toExcessNanos(daysOther));
        return compareLong(days, daysOther);
    }

    private static int compareLong(long a, long b) pure nothrow @nogc
    {
        return a < b ? -1 : a > b ? 1 : 0;
    }

    /// `<` and `>` follow `compareTo`.
    int opCmp(const FileTime other) const pure nothrow @nogc
    {
        return compareTo(other);
    }

    private enum long daysPer10000Years = 146_097L * 25L;
    private enum long secondsPer10000Years = 146_097L * 25L * 86_400L;
    private enum long seconds0000To1970 = ((146_097L * 5L) - (30L * 365L + 7L)) * 86_400L;

    private static long floorDiv(long a, long b) pure nothrow @nogc
    {
        long q = a / b;
        if ((a % b != 0) && ((a < 0) != (b < 0)))
            q--;
        return q;
    }

    private static long floorMod(long a, long b) pure nothrow @nogc
    {
        return a - floorDiv(a, b) * b;
    }

    // Java's StringBuilder append(sb, w, d): write d with w as the leading place value.
    private static void appendPlace(char[] buf, ref size_t length, long d, int w) pure nothrow @nogc
    {
        while (w > 0)
        {
            buf[length++] = cast(char)('0' + cast(int)(d / w));
            d = d % w;
            w /= 10;
        }
    }

    private static void appendUnsigned(char[] buf, ref size_t length, long value) pure nothrow @nogc
    {
        char[20] digits;
        int count = 0;
        do
        {
            digits[count++] = cast(char)('0' + cast(int)(value % 10));
            value /= 10;
        }
        while (value != 0);
        while (count > 0)
            buf[length++] = digits[--count];
    }

    /// Returns the string in ISO-8601 form, e.g. `2009-02-13T23:31:30.123Z`.
    string toString() const
    {
        long secs = 0L;
        int nanos = 0;
        if (hasUnit_ && unit_ >= TimeUnit.SECONDS)
            secs = unit_.toSeconds(value_);
        else
        {
            const instant = toInstant();
            secs = instant.getEpochSecond();
            nanos = instant.getNano();
        }
        LocalDateTime ldt;
        long year = 0;
        if (secs >= -seconds0000To1970)
        {
            const zeroSecs = secs - secondsPer10000Years + seconds0000To1970;
            const hi = floorDiv(zeroSecs, secondsPer10000Years) + 1;
            const lo = floorMod(zeroSecs, secondsPer10000Years);
            ldt = LocalDateTime.ofEpochSecond(lo - seconds0000To1970, nanos, ZoneOffset.UTC);
            year = ldt.getYear() + hi * 10_000;
        }
        else
        {
            const zeroSecs = secs + seconds0000To1970;
            const hi = zeroSecs / secondsPer10000Years;
            const lo = zeroSecs % secondsPer10000Years;
            ldt = LocalDateTime.ofEpochSecond(lo - seconds0000To1970, nanos, ZoneOffset.UTC);
            year = ldt.getYear() + hi * 10_000;
        }
        if (year <= 0)
            year = year - 1;
        char[80] buf;
        size_t length = 0;
        if (year < 0)
            buf[length++] = '-';
        const magnitude = year < 0 ? -year : year;
        if (magnitude < 10_000)
            appendPlace(buf, length, magnitude, 1000);
        else
            appendUnsigned(buf, length, magnitude);
        buf[length++] = '-';
        appendPlace(buf, length, ldt.getMonthValue(), 10);
        buf[length++] = '-';
        appendPlace(buf, length, ldt.getDayOfMonth(), 10);
        buf[length++] = 'T';
        appendPlace(buf, length, ldt.getHour(), 10);
        buf[length++] = ':';
        appendPlace(buf, length, ldt.getMinute(), 10);
        buf[length++] = ':';
        appendPlace(buf, length, ldt.getSecond(), 10);
        int fraction = ldt.getNano();
        if (fraction != 0)
        {
            buf[length++] = '.';
            int w = 100_000_000;
            while (fraction % 10 == 0)
            {
                fraction /= 10;
                w /= 10;
            }
            appendPlace(buf, length, fraction, w);
        }
        buf[length++] = 'Z';
        return buf[0 .. length].idup;
    }
}
