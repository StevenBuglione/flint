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

@("AtomicInteger reports Java's arithmetic, exchange and comparison results")
unittest
{
    auto value = new AtomicInteger(10);
    assert(value.getAndIncrement() == 10 && value.get() == 11);
    assert(value.incrementAndGet() == 12);
    assert(value.getAndDecrement() == 12 && value.decrementAndGet() == 10);
    assert(value.getAndAdd(5) == 10 && value.addAndGet(-2) == 13);
    assert(value.getAndSet(20) == 13 && value.get() == 20);
    assert(value.compareAndSet(20, 21) && value.get() == 21);
    assert(!value.compareAndSet(20, 22) && value.get() == 21);
    assert(value.compareAndExchange(21, 30) == 21 && value.get() == 30);
    assert(value.compareAndExchange(1, 2) == 30 && value.get() == 30);
    assert(value.compareAndExchangeAcquire(30, 31) == 30 && value.get() == 31);
    assert(value.compareAndExchangeRelease(31, 32) == 31 && value.get() == 32);
    assert(value.toString() == "32" && value.intValue() == 32 && value.longValue() == 32L);
    assert(value.floatValue() == 32.0f && value.doubleValue() == 32.0);
    assert(new AtomicInteger(-7).toString() == "-7");
}

@("AtomicInteger's weak and ordered operations follow Java's memory modes")
unittest
{
    auto value = new AtomicInteger(1);
    assert(!value.weakCompareAndSetPlain(2, 4));
    assert(!value.weakCompareAndSetAcquire(2, 4));
    assert(!value.weakCompareAndSetRelease(2, 4));
    assert(!value.weakCompareAndSetVolatile(2, 4));
    assert(value.weakCompareAndSetVolatile(1, 3) && value.get() == 3);
    assert(value.getPlain() == 3);
    value.setPlain(4);
    assert(value.getOpaque() == 4);
    value.setOpaque(5);
    assert(value.getAcquire() == 5);
    value.setRelease(6);
    assert(value.get() == 6);
    value.lazySet(7);
    assert(value.getAcquire() == 7);
    assert(new AtomicInteger(int.max).incrementAndGet() == int.min);
}

@("AtomicInteger accumulate operations see the previous value")
unittest
{
    import flint.java.util.function_ : IntBinaryOperator;

    auto value = new AtomicInteger(3);
    auto sum = IntBinaryOperator.of((int left, int right) => left + right);
    assert(value.getAndAccumulate(4, sum) == 3 && value.get() == 7);
    assert(value.accumulateAndGet(5, sum) == 12);
}

@("AtomicLong reports Java's arithmetic, exchange and comparison results")
unittest
{
    auto value = new AtomicLong(10);
    assert(value.getAndIncrement() == 10 && value.get() == 11);
    assert(value.incrementAndGet() == 12);
    assert(value.getAndDecrement() == 12 && value.decrementAndGet() == 10);
    assert(value.getAndAdd(5) == 10 && value.addAndGet(-2) == 13);
    assert(value.getAndSet(20) == 13 && value.get() == 20);
    assert(value.compareAndSet(20, 21) && value.get() == 21);
    assert(!value.compareAndSet(20, 22) && value.get() == 21);
    assert(value.compareAndExchange(21, 30) == 21 && value.get() == 30);
    assert(value.compareAndExchange(1, 2) == 30 && value.get() == 30);
    assert(value.compareAndExchangeAcquire(30, 31) == 30 && value.get() == 31);
    assert(value.compareAndExchangeRelease(31, 32) == 31 && value.get() == 32);
    assert(value.toString() == "32" && value.intValue() == 32 && value.longValue() == 32L);
    assert(value.floatValue() == 32.0f && value.doubleValue() == 32.0);
    assert(new AtomicLong(long.min).decrementAndGet() == long.max);
}

@("AtomicLong's weak and ordered operations follow Java's memory modes")
unittest
{
    auto value = new AtomicLong(1);
    assert(!value.weakCompareAndSetPlain(2, 4));
    assert(!value.weakCompareAndSetAcquire(2, 4));
    assert(!value.weakCompareAndSetRelease(2, 4));
    assert(!value.weakCompareAndSetVolatile(2, 4));
    assert(value.weakCompareAndSetVolatile(1, 3) && value.get() == 3);
    assert(value.getPlain() == 3);
    value.setPlain(4);
    assert(value.getOpaque() == 4);
    value.setOpaque(5);
    assert(value.getAcquire() == 5);
    value.setRelease(6);
    assert(value.get() == 6);
    value.lazySet(7);
    assert(value.getAcquire() == 7);
}

private final class CounterRace
{
    private AtomicInteger counter;
    private int increments;
    private AtomicLong total;

    this(int increments)
    {
        counter = new AtomicInteger;
        this.increments = increments;
        total = new AtomicLong;
    }

    void run() nothrow @nogc
    {
        foreach (_; 0 .. increments)
        {
            counter.incrementAndGet();
            total.addAndGet(2);
        }
    }

    int count() const nothrow @nogc
    {
        return counter.get();
    }

    long sum() const nothrow @nogc
    {
        return total.get();
    }
}

@("concurrent increments lose none")
@system unittest
{
    import core.thread : Thread;

    enum increments = 20_000;
    auto race = new CounterRace(increments);
    auto first = new Thread(&race.run);
    auto second = new Thread(&race.run);
    first.start();
    scope (failure)
        first.join();
    second.start();
    second.join();
    first.join();
    assert(race.count() == 2 * increments);
    assert(race.sum() == 4L * increments);
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
