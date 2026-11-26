module flint.java.time.zone_offset_transition_rule_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException;
import flint.java.time : DateTimeException, DayOfWeek, LocalDateTime, LocalTime, Month, ZoneOffset;
import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule, createDateTime, valueOf, values;
import std.typecons : Nullable;

@safe:

private alias TimeDefinition = ZoneOffsetTransitionRule.TimeDefinition;
private enum standard = ZoneOffset.ofHours(1);
private enum summer = ZoneOffset.ofHours(2);

@("time definition names and order match the Java enum") unittest
{
    auto first = values();
    assert(first == [TimeDefinition.UTC, TimeDefinition.WALL, TimeDefinition.STANDARD]);
    first[0] = TimeDefinition.WALL;
    assert(values()[0] == TimeDefinition.UTC && valueOf("STANDARD") == TimeDefinition.STANDARD);
    foreach (bad; ["wall", "", null])
    {
        try
        {
            valueOf(bad);
            assert(false);
        }
        catch (IllegalArgumentException error)
        {
            assert(error.getMessage() == "No enum constant java.time.zone.ZoneOffsetTransitionRule.TimeDefinition."
                    ~ bad);
        }
    }
    try
    {
        valueOf(null);
        assert(false);
    }
    catch (IllegalArgumentException error)
    {
        assert(error.getMessage() == "No enum constant java.time.zone.ZoneOffsetTransitionRule.TimeDefinition.");
    }
}

@("a negative day rule selects the last matching weekday without allocation") unittest
{
    const time = LocalTime.of(2, 0);
    const allocated = GC.stats().allocatedInCurrentThread;
    const gapRule = ZoneOffsetTransitionRule.of(Month.MARCH, -1, DayOfWeek.SUNDAY, time, false,
            TimeDefinition.WALL, standard, standard, summer);
    const gap = gapRule.createTransition(2024);
    assert(gapRule.getMonth() == Month.MARCH && gapRule.getDayOfMonthIndicator() == -1);
    assert(gapRule.getDayOfWeek().get() == DayOfWeek.SUNDAY);
    assert(gapRule.getLocalTime() == time && !gapRule.isMidnightEndOfDay());
    assert(gapRule.getTimeDefinition() == TimeDefinition.WALL);
    assert(gapRule.getStandardOffset() == standard && gapRule.getOffsetBefore() == standard);
    assert(gapRule.getOffsetAfter() == summer);
    assert(gapRule.hashCode() == 235_933_657);
    assert(gap.toEpochSecond() == 1_711_846_800 && gap.isGap());
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assert(gap.getDateTimeBefore() == LocalDateTime.of(2024, 3, 31, 2, 0));
    assert(gapRule.toString() == "TransitionRule[Gap +01:00 to +02:00, SUNDAY on or before last day of MARCH"
            ~ " at 02:00 WALL, standard offset +01:00]");
}

@("midnight and out-of-month weekdays apply the selected time definition") unittest
{
    const overlap = ZoneOffsetTransitionRule.of(Month.OCTOBER, -2, DayOfWeek.SUNDAY,
            LocalTime.MIDNIGHT, true, TimeDefinition.STANDARD, standard, summer, standard);
    assert(overlap.isMidnightEndOfDay() && overlap.hashCode() == 55_290);
    assert(overlap.createTransition(2024).getDateTimeBefore() == LocalDateTime.of(2024, 10, 28, 1, 0));
    assert(overlap.toString() == "TransitionRule[Overlap +02:00 to +01:00, SUNDAY on or before last day minus 1"
            ~ " of OCTOBER at 24:00 STANDARD, standard offset +01:00]");

    const nextYear = ZoneOffsetTransitionRule.of(Month.DECEMBER, 30, DayOfWeek.WEDNESDAY,
            LocalTime.of(23, 59, 59), false, TimeDefinition.UTC, standard, standard, summer);
    assert(nextYear.createTransition(2024).getDateTimeBefore() == LocalDateTime.of(2025, 1, 2, 0, 59, 59));
    assert(nextYear.hashCode() == -1_463_827_480 && !overlap.equals(nextYear));
    assert(TimeDefinition.UTC.createDateTime(LocalDateTime.of(2025, 1, 1, 23, 59, 59), standard,
            standard) == LocalDateTime.of(2025, 1, 2, 0, 59, 59));
}

@("an absent weekday preserves the resolved month day and permits unchanged offsets") unittest
{
    const same = ZoneOffsetTransitionRule.of(Month.FEBRUARY, -1, Nullable!DayOfWeek.init,
            LocalTime.MIDNIGHT, false, TimeDefinition.WALL, standard, summer, summer);
    const transition = same.createTransition(2024);
    assert(same.getDayOfWeek().isNull && same.equals(same) && same.hashCode() == 1_517);
    assert(transition.toEpochSecond() == 1_709_157_600);
    assert(transition.getDateTimeBefore() == LocalDateTime.of(2024, 2, 29, 0, 0));
    assert(transition.getDateTimeBefore() == transition.getDateTimeAfter());
    assert(!transition.isGap() && !transition.isOverlap());
    assert(transition.isValidOffset(summer) && !transition.isValidOffset(standard));
    assert(same.createTransition(2025).getDateTimeBefore() == LocalDateTime.of(2025, 2, 28, 0, 0));
    assert(same.toString() == "TransitionRule[Overlap +02:00 to +02:00, FEBRUARY -1 at 00:00 WALL,"
            ~ " standard offset +01:00]");
}

@("rule factory validates days, midnight and subsecond input in Java order") unittest
{
    void rejects(int day, LocalTime time, bool endOfDay, string message)
    {
        try
        {
            ZoneOffsetTransitionRule.of(Month.MARCH, day, Nullable!DayOfWeek.init, time, endOfDay,
                    TimeDefinition.WALL, standard, standard, summer);
            assert(false);
        }
        catch (IllegalArgumentException error)
        {
            assert(error.getMessage() == message);
        }
    }

    const fractionalMidnight = LocalTime.of(0, 0, 0, 1);
    foreach (day; [-29, 0, 32])
        rejects(day, fractionalMidnight, true,
                "Day of month indicator must be between -28 and 31 inclusive excluding zero");
    rejects(1, fractionalMidnight, true, "Time must be midnight when end of day flag is true");
    rejects(1, fractionalMidnight, false, "Time's nano-of-second must be zero");
}

@("rule equality compares each calendar, time and offset field") unittest
{
    ZoneOffsetTransitionRule rule(Month month = Month.SEPTEMBER, int day = -7,
            Nullable!DayOfWeek weekday = Nullable!DayOfWeek(DayOfWeek.WEDNESDAY),
            LocalTime time = LocalTime.MIDNIGHT, bool endOfDay = false,
            TimeDefinition definition = TimeDefinition.WALL,
            ZoneOffset standardOffset = standard, ZoneOffset before = standard, ZoneOffset after = summer)
    {
        return ZoneOffsetTransitionRule.of(month, day, weekday, time, endOfDay, definition,
                standardOffset, before, after);
    }

    const base = rule();
    assert(base.equals(rule()));
    assert(base.hashCode() == rule().hashCode());
    assert(base.createTransition(2024).getDateTimeBefore() == LocalDateTime.of(2024, 9, 18, 0, 0));
    assert(!base.equals(rule(Month.OCTOBER)));
    assert(!base.equals(rule(Month.SEPTEMBER, -6)));
    assert(!base.equals(rule(Month.SEPTEMBER, -7, Nullable!DayOfWeek.init)));
    assert(!base.equals(rule(Month.SEPTEMBER, -7, Nullable!DayOfWeek(DayOfWeek.THURSDAY))));
    foreach (other; [
        rule(Month.SEPTEMBER, -7, base.getDayOfWeek(), LocalTime.NOON),
        rule(Month.SEPTEMBER, -7, base.getDayOfWeek(), LocalTime.MIDNIGHT, true),
        rule(Month.SEPTEMBER, -7, base.getDayOfWeek(), LocalTime.MIDNIGHT, false,
                TimeDefinition.UTC),
        rule(Month.SEPTEMBER, -7, base.getDayOfWeek(), LocalTime.MIDNIGHT, false,
                TimeDefinition.WALL, ZoneOffset.UTC),
        rule(Month.SEPTEMBER, -7, base.getDayOfWeek(), LocalTime.MIDNIGHT, false,
                TimeDefinition.WALL, standard, ZoneOffset.UTC),
        rule(Month.SEPTEMBER, -7, base.getDayOfWeek(), LocalTime.MIDNIGHT, false,
                TimeDefinition.WALL, standard, standard, ZoneOffset.UTC)
    ])
        assert(!base.equals(other));
}

@("a fixed February 29 is checked when the rule is applied") unittest
{
    const rule = ZoneOffsetTransitionRule.of(Month.FEBRUARY, 29, Nullable!DayOfWeek.init,
            LocalTime.MIDNIGHT, false, TimeDefinition.WALL, standard, standard, summer);
    assert(rule.createTransition(2024).getDateTimeBefore() == LocalDateTime.of(2024, 2, 29, 0, 0));
    try
    {
        rule.createTransition(2023);
        assert(false);
    }
    catch (DateTimeException)
    {
    }
}

@("required rule fields and equality take typed values") unittest
{
    alias of = ZoneOffsetTransitionRule.of;
    static assert(!is(typeof(of(null, 1, DayOfWeek.MONDAY, LocalTime.MIDNIGHT, false,
            TimeDefinition.WALL, standard, standard, summer))));
    static assert(!is(typeof(of(Month.JANUARY, 1, DayOfWeek.MONDAY, null, false,
            TimeDefinition.WALL, standard, standard, summer))));
    static assert(!is(typeof(of(Month.JANUARY, 1, DayOfWeek.MONDAY, LocalTime.MIDNIGHT, false,
            null, standard, standard, summer))));
    static assert(!is(typeof(of(Month.JANUARY, 1, DayOfWeek.MONDAY, LocalTime.MIDNIGHT, false,
            TimeDefinition.WALL, null, standard, summer))));
    static assert(!is(typeof(of(Month.JANUARY, 1, DayOfWeek.MONDAY, LocalTime.MIDNIGHT, false,
            TimeDefinition.WALL, standard, null, summer))));
    static assert(!is(typeof(of(Month.JANUARY, 1, DayOfWeek.MONDAY, LocalTime.MIDNIGHT, false,
            TimeDefinition.WALL, standard, standard, null))));
    static assert(!is(typeof(ZoneOffsetTransitionRule.init.equals(null))));
    static assert(!is(typeof(ZoneOffsetTransitionRule.init.equals("rule"))));
}
