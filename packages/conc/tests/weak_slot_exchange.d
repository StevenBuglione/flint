module flint.conc.weak_slot_exchange_test;

import core.memory : GC;
import flint.conc.slot : ProcessSlot;

@safe:

private interface Reading
{
    int read() const nothrow @nogc;
}

private interface LeftReading : Reading
{
}

private interface RightReading : Reading
{
}

private final class Sample : LeftReading, RightReading
{
    int read() const nothrow @nogc
    {
        return 17;
    }
}

private alias Update = bool delegate(Reading, Reading) shared nothrow @nogc @safe;

private void retry(scope Update update, Reading expected, Reading desired) nothrow @nogc
{
    foreach (attempt; 0 .. 10_000)
        if (update(expected, desired))
            return;
    assert(false, "weak update did not succeed in bounded retries");
}

private void verifyMode(scope Update update, Reading storedView, Reading otherView, Reading unrelated) nothrow @nogc
{
    foreach (iteration; 0 .. 256)
    {
        assert(!update(unrelated, null));
        retry(update, otherView, null);
        retry(update, null, storedView);
    }
}

@("ProcessSlot weak updates compare object identity across interface views without GC allocation")
unittest
{
    shared ProcessSlot!Reading slot;
    auto same = new Sample;
    Reading left = cast(LeftReading) same;
    Reading right = cast(RightReading) same;
    Reading unrelated = new Sample;
    slot.setVolatile(left);

    const usedBefore = GC.stats().usedSize;
    const collectionsBefore = GC.profileStats().numCollections;
    verifyMode(&slot.weakCompareAndSetPlain, left, right, unrelated);
    verifyMode(&slot.weakCompareAndSetAcquire, left, right, unrelated);
    verifyMode(&slot.weakCompareAndSetRelease, left, right, unrelated);
    verifyMode(&slot.weakCompareAndSetVolatile, left, right, unrelated);
    assert(GC.profileStats().numCollections == collectionsBefore);
    assert(GC.stats().usedSize == usedBefore);
    assert(cast(Object) slot.getVolatile() is same && slot.getVolatile().read() == 17);
}
