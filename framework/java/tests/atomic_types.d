module atomic_types;

import flint.java.util.concurrent.atomic : OldBoolean = AtomicBoolean, OldInteger = AtomicInteger, OldLong = AtomicLong;
import flint.java.util.concurrent.atomic.atomicboolean : AtomicBoolean;
import flint.java.util.concurrent.atomic.atomicinteger : AtomicInteger;
import flint.java.util.concurrent.atomic.atomiclong : AtomicLong;

@safe:
@("legacy imports name the same atomic classes as the canonical leaves")
unittest
{
    static assert(is(OldBoolean == AtomicBoolean));
    static assert(is(OldInteger == AtomicInteger));
    static assert(is(OldLong == AtomicLong));
}

@("compareAndExchange returns the witness on success and on failure")
unittest
{
    auto value = new AtomicBoolean;
    assert(value.compareAndExchange(true, true) == false);
    assert(!value.get());
    assert(value.compareAndExchange(false, true) == false);
    assert(value.get());
    assert(value.compareAndExchangeAcquire(false, false) == true);
    assert(value.get());
    assert(value.compareAndExchangeRelease(true, false) == true);
    assert(!value.get());
}

@("plain, opaque and release operations observe the current boolean")
unittest
{
    auto value = new AtomicBoolean(true);
    assert(value.getPlain());
    value.setPlain(false);
    assert(!value.getOpaque());
    value.setOpaque(true);
    assert(value.getAcquire());
    value.setRelease(false);
    assert(!value.get());
    value.lazySet(true);
    assert(value.getAcquire());
    assert(value.toString() == "true");
    assert(value.getAndSet(false));
    assert(value.toString() == "false");
}

@("a weak comparison with a mismatching witness cannot write")
unittest
{
    auto value = new AtomicBoolean(true);
    assert(!value.weakCompareAndSetPlain(false, false));
    assert(!value.weakCompareAndSetAcquire(false, false));
    assert(!value.weakCompareAndSetRelease(false, false));
    assert(!value.weakCompareAndSetVolatile(false, false));
    assert(value.get());
    const applied = value.weakCompareAndSetVolatile(true, false);
    assert(value.get() != applied);
}

private final class TransitionRace
{
    import core.atomic : atomicLoad, atomicOp;

    private AtomicBoolean published;
    private shared uint wins;

    this()
    {
        published = new AtomicBoolean;
    }

    void tryPublish() nothrow @nogc
    {
        if (published.compareAndSet(false, true))
            atomicOp!"+="(wins, 1u);
    }

    uint winners() const nothrow @nogc
    {
        return atomicLoad(wins);
    }
}

@("only one publisher can claim an atomic flag")
@system unittest
{
    import core.thread : Thread;

    auto race = new TransitionRace;
    auto first = new Thread(&race.tryPublish);
    auto second = new Thread(&race.tryPublish);
    first.start();
    scope (failure)
        first.join();
    second.start();
    second.join();
    first.join();
    assert(race.winners() == 1);
}
