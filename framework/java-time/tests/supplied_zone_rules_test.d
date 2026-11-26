module flint.java.time.supplied_zone_rules_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.time : DateTimeException, DayOfWeek, Duration, Instant, LocalDateTime, LocalTime, Month, ZoneOffset;
import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;
import flint.java.time.zone.zonerules : ZoneRules;
import flint.java.util : ArrayList, List;
import std.typecons : Nullable;

@safe:

private enum winter = ZoneOffset.ofHours(1);
private enum summer = ZoneOffset.ofHours(2);
private alias TimeDefinition = ZoneOffsetTransitionRule.TimeDefinition;

private ZoneOffsetTransition gap()
{
    return ZoneOffsetTransition.of(LocalDateTime.of(2024, 3, 31, 2, 0), winter, summer);
}

private ZoneOffsetTransition overlap()
{
    return ZoneOffsetTransition.of(LocalDateTime.of(2024, 10, 27, 3, 0), summer, winter);
}

private ZoneOffsetTransitionRule annual(Month month, int hour, ZoneOffset before, ZoneOffset after)
{
    return ZoneOffsetTransitionRule.of(month, -1, DayOfWeek.SUNDAY, LocalTime.of(hour, 0), false,
            TimeDefinition.WALL, winter, before, after);
}

private List!ZoneOffsetTransitionRule recurring()
{
    return List!ZoneOffsetTransitionRule.of(annual(Month.MARCH, 2, winter, summer),
            annual(Month.OCTOBER, 3, summer, winter));
}

private ZoneRules sampleRules()
{
    const standard = ZoneOffsetTransition.of(LocalDateTime.of(2010, 1, 1, 0, 0), ZoneOffset.UTC, winter);
    return ZoneRules.of(ZoneOffset.UTC, winter, List!ZoneOffsetTransition.of(standard),
            List!ZoneOffsetTransition.of(gap(), overlap()), recurring());
}

@("supplied transitions match the Java gap and overlap boundaries") unittest
{
    const rules = sampleRules();
    const spring = gap();
    const autumn = overlap();
    const gapStart = spring.getDateTimeBefore();
    const gapEnd = spring.getDateTimeAfter();
    const overlapStart = autumn.getDateTimeAfter();
    const overlapEnd = autumn.getDateTimeBefore();
    const allocated = GC.stats().allocatedInCurrentThread;
    assert(!rules.isFixedOffset());
    assert(rules.getOffset(spring.getInstant()) == summer);
    assert(rules.getOffset(autumn.getInstant()) == winter);
    assert(rules.getOffset(gapStart) == winter && rules.getOffset(gapEnd) == summer);
    assert(rules.getTransition(gapStart).get() == spring && rules.getTransition(gapEnd).isNull);
    assert(rules.getOffset(overlapStart) == summer && rules.getOffset(overlapEnd) == winter);
    assert(rules.getTransition(overlapStart).get() == autumn && rules.getTransition(overlapEnd).isNull);
    assert(rules.previousTransition(spring.getInstant()).isNull);
    assert(rules.previousTransition(Instant.ofEpochSecond(spring.toEpochSecond(), 1)).get() == spring);
    assert(rules.nextTransition(spring.getInstant()).get() == autumn);
    assert(rules.getStandardOffset(Instant.EPOCH) == ZoneOffset.UTC);
    assert(rules.getDaylightSavings(Instant.EPOCH) == Duration.ofSeconds(3_600));
    assert(rules.isValidOffset(overlapStart, winter) && rules.isValidOffset(overlapStart, summer));
    assert(!rules.isValidOffset(gapStart, winter) && !rules.isValidOffset(gapStart, summer));
    assert(rules.hashCode() == 1_076_119_729);
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assert(rules.getValidOffsets(gapStart).isEmpty());
    assert(rules.getValidOffsets(overlapStart).toArray() == [summer, winter]);
    assert(rules.getValidOffsets(gapEnd).toArray() == [summer]);
    assert(rules.toString() == "ZoneRules[currentStandardOffset=+01:00]");
    assert(rules.equals(sampleRules()) && !rules.equals(ZoneRules.of(winter)));
    assert(rules == sampleRules() && rules.toHash() == sampleRules().toHash());
}

@("final rules apply beyond the historical list without allocation") unittest
{
    const rules = sampleRules();
    const futureGap = LocalDateTime.of(2040, 3, 25, 2, 45);
    const futureOverlap = LocalDateTime.of(2040, 10, 28, 2, 15);
    const january = LocalDateTime.of(2040, 1, 1, 0, 0).toInstant(ZoneOffset.UTC);
    const previous = LocalDateTime.of(2039, 10, 30, 3, 0);
    const next = LocalDateTime.of(2040, 3, 25, 2, 0);
    const allocated = GC.stats().allocatedInCurrentThread;
    assert(rules.getOffset(futureGap) == winter && rules.getTransition(futureGap).get().isGap());
    assert(rules.getOffset(futureOverlap) == summer && rules.getTransition(futureOverlap).get().isOverlap());
    assert(rules.previousTransition(january).get().getDateTimeBefore() == previous);
    assert(rules.nextTransition(january).get().getDateTimeBefore() == next);
    assert(rules.getOffset(january) == winter && !rules.isDaylightSavings(january));
    assert(GC.stats().allocatedInCurrentThread == allocated);
}

@("an overlap starting exactly where a gap ends wins at their common boundary") unittest
{
    const forward = gap();
    const backward = ZoneOffsetTransition.of(LocalDateTime.of(2024, 3, 31, 4, 0), summer, winter);
    const rules = ZoneRules.of(winter, winter, List!ZoneOffsetTransition.of(),
            List!ZoneOffsetTransition.of(forward, backward), List!ZoneOffsetTransitionRule.of());
    const boundary = forward.getDateTimeAfter();
    assert(boundary == backward.getDateTimeAfter());
    assert(rules.getTransition(boundary).get() == backward);
    assert(rules.getValidOffsets(boundary).toArray() == [summer, winter]);
}

@("factory snapshots lists and ignores null dates only when the relevant history is empty") unittest
{
    auto history = new ArrayList!ZoneOffsetTransition([gap(), overlap()]);
    const rules = ZoneRules.of(winter, winter, List!ZoneOffsetTransition.of(), history, recurring());
    history.clear();
    assert(rules.getTransitions().size() == 2 && rules.getTransitionRules().size() == 2);
    assert(rules.getStandardOffset(Nullable!Instant.init) == winter);
    try
    {
        rules.getOffset(Nullable!Instant.init);
        assert(false);
    }
    catch (NullPointerException)
    {
    }

    const orphan = ZoneRules.of(winter, summer, List!ZoneOffsetTransition.of(),
            List!ZoneOffsetTransition.of(), recurring());
    assert(!orphan.isFixedOffset() && orphan.getOffset(Nullable!Instant.init) == summer);
    assert(orphan.nextTransition(Nullable!Instant.init).isNull);
    assert(orphan.getDaylightSavings(Nullable!Instant.init) == Duration.ofSeconds(3_600));
}

@("future rule errors occur at the Java query boundary") unittest
{
    const malformed = ZoneOffsetTransitionRule.of(Month.FEBRUARY, 31, Nullable!DayOfWeek.init,
            LocalTime.MIDNIGHT, false, TimeDefinition.WALL, winter, winter, summer);
    const rules = ZoneRules.of(winter, winter, List!ZoneOffsetTransition.of(),
            List!ZoneOffsetTransition.of(gap(), overlap()), List!ZoneOffsetTransitionRule.of(malformed));
    try
    {
        rules.getOffset(LocalDateTime.of(2040, 6, 1, 0, 0).toInstant(ZoneOffset.UTC));
        assert(false);
    }
    catch (DateTimeException error)
    {
        assert(error.getMessage() == "Invalid date 'FEBRUARY 31'");
    }

    auto excess = new ZoneOffsetTransitionRule[17];
    try
    {
        ZoneRules.of(winter, winter, List!ZoneOffsetTransition.of(),
                List!ZoneOffsetTransition.of(), List!ZoneOffsetTransitionRule.of(excess));
        assert(false);
    }
    catch (IllegalArgumentException error)
    {
        assert(error.getMessage() == "Too many transition rules");
    }
}

@("the supplied factory preserves empty-rule identity and rejects an absent standard offset") unittest
{
    auto empty = List!ZoneOffsetTransition.of();
    auto noAnnual = List!ZoneOffsetTransitionRule.of();
    const supplied = ZoneRules.of(winter, winter, empty, empty, noAnnual);
    const fixed = ZoneRules.of(winter);
    assert(supplied.isFixedOffset() && supplied == fixed && supplied.hashCode() == fixed.hashCode());
    try
    {
        ZoneRules.of(Nullable!ZoneOffset.init, Nullable!ZoneOffset(winter), empty, empty, noAnnual);
        assert(false);
    }
    catch (NullPointerException error)
    {
        assert(error.getMessage() == "baseStandardOffset");
    }
}
