/// Pure calendar arithmetic for Java's default Gregorian/Julian cutover.
module flint.java.util.internal.gregorian;

@safe:

// Calendar's import list otherwise retains the arithmetic module record even when no arithmetic is used.
// Keep this leaf import-free and free of runtime initialization and TLS. Keep its tests in tests/.
version (LDC) pragma(LDC_no_moduleinfo);

/// Milliseconds in a day.
package(flint.java) enum long DAY = 86_400_000;

/// The epoch day of 1582-10-15, the first Gregorian day (GregorianCalendar's default cutover).
package(flint.java) enum long CUTOVER_DAY = -141_427;

package(flint.java) struct GregorianFields
{
    long year; // astronomical: 1 BC is 0
    int month; // 1 to 12
    int day;
    int hour;
    int minute;
    int second;
    int millis;
    long epochDay; // days since 1970-01-01, in the zone

    int yearOfEra() const pure nothrow @nogc
    {
        return cast(int)(year > 0 ? year : 1 - year);
    }

    int dayOfYear() const pure nothrow @nogc
    {
        return cast(int)(epochDay - januaryFirst(year) + 1);
    }

    int weekday() const pure nothrow @nogc
    {
        return dayOfWeek(epochDay);
    }
}

// The fields of `millis` at `offset` milliseconds from UTC.
package(flint.java) GregorianFields fieldsOf(long millis, long offset) pure nothrow @nogc
{
    auto epochDay = floorDiv(millis, DAY);
    long ofDay = floorMod(millis, DAY) + offset;
    epochDay += floorDiv(ofDay, DAY);
    ofDay = floorMod(ofDay, DAY);
    long year;
    int month, day;
    if (epochDay >= CUTOVER_DAY)
        gregorianDate(epochDay, year, month, day);
    else
        julianDate(epochDay, year, month, day);
    return GregorianFields(year, month, day, cast(int)(ofDay / 3_600_000),
            cast(int)(ofDay / 60_000 % 60), cast(int)(ofDay / 1000 % 60), cast(int)(ofDay % 1000), epochDay);
}

// The epoch day of a date given leniently (any month0 and day, carried over), Gregorian when that day is on or after
// the cutover and Julian before.
package(flint.java) long epochDayOf(long year, long month0, long day) pure nothrow @nogc
{
    const y = year + floorDiv(month0, 12);
    const m = cast(int) floorMod(month0, 12) + 1;
    const gregorian = gregorianDays(y, m, 1) + day - 1;
    return gregorian >= CUTOVER_DAY ? gregorian : julianDays(y, m, 1) + day - 1;
}

package(flint.java) bool gregorianYear(long year, int month) pure nothrow @nogc
{
    return year > 1582 || (year == 1582 && month > 10);
}

// The last day of the month. October 1582 still ends on the 31st, though the cutover makes it 21 days long (the
// 5th to the 14th do not exist); `add` only needs the last day.
package(flint.java) int monthLength(long year, int month, bool gregorian) pure nothrow @nogc
{
    static immutable int[12] days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month != 2)
        return days[month - 1];
    const leap = gregorian ? (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) : floorMod(year, 4) == 0;
    return leap ? 29 : 28;
}

// 1 for Sunday to 7 for Saturday.
package(flint.java) int dayOfWeek(long epochDay) pure nothrow @nogc
{
    return cast(int) floorMod(epochDay + 4, 7) + 1;
}

// The epoch day of January 1 of `year`, in the calendar in force that day.
package(flint.java) long januaryFirst(long year) pure nothrow @nogc
{
    const gregorian = gregorianDays(year, 1, 1);
    return gregorian >= CUTOVER_DAY ? gregorian : julianDays(year, 1, 1);
}

// The Sunday that starts week 1 of `year`: the week holding January 1 (en_US).
package(flint.java) long weekOneStart(long year) pure nothrow @nogc
{
    const jan1 = januaryFirst(year);
    return jan1 - (dayOfWeek(jan1) - 1);
}

// Howard Hinnant's days_from_civil and civil_from_days, with floor division for any year.
private long gregorianDays(long year, int month, int day) pure nothrow @nogc
{
    const marchYear = month <= 2 ? year - 1 : year;
    const era = floorDiv(marchYear, 400);
    const yoe = marchYear - era * 400;
    const doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1;
    const doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146_097 + doe - 719_468;
}

private void gregorianDate(long epochDay, out long year, out int month, out int day) pure nothrow @nogc
{
    const z = epochDay + 719_468;
    const era = floorDiv(z, 146_097);
    const doe = z - era * 146_097;
    const yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    day = cast(int)(doy - (153 * mp + 2) / 5 + 1);
    month = cast(int)(mp < 10 ? mp + 3 : mp - 9);
    year = yoe + era * 400 + (month <= 2 ? 1 : 0);
}

// The Julian calendar through the Julian day number (2440588 is 1970-01-01).
private long julianDays(long year, int month, int day) pure nothrow @nogc
{
    const a = (14 - month) / 12;
    const shifted = year + 4800 - a;
    const m = month + 12 * a - 3;
    return day + (153 * m + 2) / 5 + 365 * shifted + floorDiv(shifted, 4) - 32_083 - 2_440_588;
}

private void julianDate(long epochDay, out long year, out int month, out int day) pure nothrow @nogc
{
    const c = epochDay + 2_440_588 + 32_082;
    const d = floorDiv(4 * c + 3, 1461);
    const e = c - floorDiv(1461 * d, 4);
    const m = (5 * e + 2) / 153;
    day = cast(int)(e - (153 * m + 2) / 5 + 1);
    month = cast(int)(m + 3 - 12 * (m / 10));
    year = d - 4800 + m / 10;
}

package(flint.java) long floorDiv(long x, long y) pure nothrow @nogc
{
    const q = x / y;
    return (x % y != 0 && ((x < 0) != (y < 0))) ? q - 1 : q;
}

package(flint.java) long floorMod(long x, long y) pure nothrow @nogc
{
    return x - floorDiv(x, y) * y;
}
