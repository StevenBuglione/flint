module flint.java.time.zone_offset_transition_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException;
import flint.java.time : LocalDateTime, ZoneOffset;
import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
import std.typecons : Nullable;

@safe:

@("a forward transition describes a gap using its before offset") unittest
{
    const start = LocalDateTime.of(2024, 3, 10, 2, 0);
    const before = ZoneOffset.ofHours(-5);
    const after = ZoneOffset.ofHours(-4);
    const gap = ZoneOffsetTransition.of(start, before, after);
    const allocated = GC.stats().allocatedInCurrentThread;
    assert(gap.isGap() && !gap.isOverlap());
    assert(!gap.isValidOffset(before) && !gap.isValidOffset(after));
    assert(!gap.isValidOffset(Nullable!ZoneOffset.init));
    assert(gap.getOffsetBefore() == before && gap.getOffsetAfter() == after);
    assert(gap.getInstant().getEpochSecond() == 1_710_054_000 && gap.toEpochSecond() == 1_710_054_000);
    assert(gap.getInstant().getNano() == 0 && gap.getDuration().getSeconds() == 3_600);
    assert(gap.getDateTimeBefore() == start && gap.getDateTimeAfter() == LocalDateTime.of(2024, 3, 10, 3, 0));
    assert(gap.hashCode() == 1_500_594_185);

    const tie = ZoneOffsetTransition.of(gap.getDateTimeAfter(), after, ZoneOffset.ofHours(-3));
    assert(gap.compareTo(tie) == 0 && !gap.equals(tie));
    assert(gap.equals(ZoneOffsetTransition.of(start, before, after)));
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assert(gap.toString() == "Transition[Gap at 2024-03-10T02:00-05:00 to -04:00]");
}

@("a backward transition preserves second precision across midnight") unittest
{
    const start = LocalDateTime.of(1910, 10, 1, 0, 10, 8);
    const before = ZoneOffset.ofTotalSeconds(3_464);
    const after = ZoneOffset.ofTotalSeconds(1_213);
    const overlap = ZoneOffsetTransition.of(start, before, after);
    assert(overlap.isOverlap() && !overlap.isGap());
    assert(overlap.isValidOffset(before) && overlap.isValidOffset(after));
    assert(overlap.isValidOffset(Nullable!ZoneOffset(after)));
    assert(!overlap.isValidOffset(Nullable!ZoneOffset.init) && !overlap.isValidOffset(ZoneOffset.UTC));
    assert(overlap.getDuration().getSeconds() == -2_251 && overlap.toEpochSecond() == -1_869_871_656);
    assert(overlap.getDateTimeAfter() == LocalDateTime.of(1910, 9, 30, 23, 32, 37));
    assert(overlap.compareTo(ZoneOffsetTransition.init) == -1);
    assert(ZoneOffsetTransition.init.compareTo(overlap) == 1);
    assert(overlap.hashCode() == -1_961_263_228);
    assert(overlap.toString() == "Transition[Overlap at 1910-10-01T00:10:08+00:57:44 to +00:20:13]");
}

@("transition factories check equal offsets before sub-second precision") unittest
{
    const fractional = LocalDateTime.of(2001, 2, 3, 4, 5, 6, 7);
    void rejects(ZoneOffset after, string message)
    {
        try
        {
            ZoneOffsetTransition.of(fractional, ZoneOffset.UTC, after);
            assert(false);
        }
        catch (IllegalArgumentException error)
        {
            assert(error.getMessage() == message);
        }
    }

    rejects(ZoneOffset.UTC, "Offsets must not be equal");
    rejects(ZoneOffset.MAX, "Nano-of-second must be zero");
}
