module flint.java.time.fixed_zone_rules_test;

import core.memory : GC;
import flint.java.lang : NullPointerException, UnsupportedOperationException;
import flint.java.time : Duration, Instant, LocalDateTime, ZoneOffset;
import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;
import flint.java.time.zone.zonerules : ZoneRules;
import std.typecons : Nullable;

@safe:

@("fixed rules give the same offset at both date limits and allocate no query storage") unittest
{
    const offset = ZoneOffset.ofTotalSeconds(-16_211);
    const instant = Instant.ofEpochSecond(30_000_000_000L);
    const allocated = GC.stats().allocatedInCurrentThread;
    const rules = ZoneRules.of(offset);
    assert(rules.isFixedOffset());
    assert(rules.getOffset(instant) == offset);
    assert(rules.getOffset(LocalDateTime.MIN) == offset && rules.getOffset(LocalDateTime.MAX) == offset);
    assert(rules.getOffset(Nullable!Instant.init) == offset);
    assert(rules.getOffset(Nullable!LocalDateTime.init) == offset);
    assert(rules.getStandardOffset(instant) == offset && rules.getStandardOffset(Nullable!Instant.init) == offset);
    assert(rules.getDaylightSavings(instant) == Duration.ZERO);
    assert(rules.getDaylightSavings(Nullable!Instant.init) == Duration.ZERO);
    assert(!rules.isDaylightSavings(instant) && !rules.isDaylightSavings(Nullable!Instant.init));
    assert(rules.isValidOffset(LocalDateTime.MIN, offset));
    assert(rules.isValidOffset(Nullable!LocalDateTime.init, offset));
    assert(!rules.isValidOffset(LocalDateTime.MAX, ZoneOffset.UTC));
    assert(!rules.isValidOffset(LocalDateTime.MIN, Nullable!ZoneOffset.init));
    assert(!rules.isValidOffset(Nullable!LocalDateTime.init, Nullable!ZoneOffset.init));
    assert(rules.getTransition(LocalDateTime.MIN).isNull);
    assert(rules.getTransition(Nullable!LocalDateTime.init).isNull);
    assert(rules.nextTransition(instant).isNull && rules.previousTransition(instant).isNull);
    assert(rules.nextTransition(Nullable!Instant.init).isNull);
    assert(rules.previousTransition(Nullable!Instant.init).isNull);
    assert(rules.equals(ZoneRules.of(offset)) && !rules.equals(ZoneRules.of(ZoneOffset.UTC)));
    assert(rules.hashCode() == 1 && ZoneRules.init.hashCode() == 1);
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assert(rules.toString() == "ZoneRules[currentStandardOffset=-04:30:11]");
    assert(ZoneRules.init.toString() == "ZoneRules[currentStandardOffset=Z]");
}

@("fixed rules return immutable singleton offsets and empty transition lists") unittest
{
    const offset = ZoneOffset.ofHours(4);
    const rules = ZoneRules.of(offset);
    auto offsets = rules.getValidOffsets(LocalDateTime.MAX);
    auto withoutDate = rules.getValidOffsets(Nullable!LocalDateTime.init);
    assert(offsets.size() == 1 && offsets.get(0) == offset);
    assert(withoutDate.size() == 1 && withoutDate.get(0) == offset);
    auto transitions = rules.getTransitions();
    auto recurring = rules.getTransitionRules();
    assert(transitions.isEmpty() && recurring.isEmpty());

    void immutableList(void delegate() @safe change)
    {
        try
        {
            change();
            assert(false);
        }
        catch (UnsupportedOperationException)
        {
        }
    }

    immutableList(() { offsets.add(ZoneOffset.UTC); });
    immutableList(() { transitions.add(ZoneOffsetTransition.init); });
    immutableList(() { recurring.add(ZoneOffsetTransitionRule.init); });
}

@("the fixed rules factory rejects an absent offset") unittest
{
    try
    {
        ZoneRules.of(Nullable!ZoneOffset.init);
        assert(false);
    }
    catch (NullPointerException error)
    {
        assert(error.getMessage() == "offset");
    }
    const present = Nullable!ZoneOffset(ZoneOffset.MAX);
    assert(ZoneRules.of(present).getOffset(Instant.EPOCH) == ZoneOffset.MAX);
}
