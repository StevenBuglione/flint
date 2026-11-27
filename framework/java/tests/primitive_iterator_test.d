module flint.java.primitive_iterator_test;

import flint.java.lang : NullPointerException;
import flint.java.util : Iterator, NoSuchElementException;
import flint.java.util.function_.doubleconsumer : DoubleConsumer;
import flint.java.util.function_.intconsumer : IntConsumer;
import flint.java.util.function_.longconsumer : LongConsumer;
import flint.java.util.primitiveiterator : PrimitiveIterator;

@safe:

private final class Ints : PrimitiveIterator!(int, IntConsumer).OfInt
{
    private int cursor;
    private immutable int end;
    int availabilityChecks;

    mixin PrimitiveIterator!(int, IntConsumer).OfInt.Defaults;

    this(int end)
    {
        this.end = end;
    }

    bool hasNext()
    {
        ++availabilityChecks;
        return cursor < end;
    }

    int nextInt()
    {
        if (cursor == end)
            throw new NoSuchElementException("end");
        return ++cursor;
    }

    void remove()
    {
        assert(false);
    }
}

private final class Longs : PrimitiveIterator!(long, LongConsumer).OfLong
{
    private long cursor;

    mixin PrimitiveIterator!(long, LongConsumer).OfLong.Defaults;

    bool hasNext()
    {
        return cursor < 3;
    }

    long nextLong()
    {
        return ++cursor * 10_000_000_000L;
    }

    void remove()
    {
        assert(false);
    }
}

private final class Doubles : PrimitiveIterator!(double, DoubleConsumer).OfDouble
{
    private int cursor;

    mixin PrimitiveIterator!(double, DoubleConsumer).OfDouble.Defaults;

    bool hasNext()
    {
        return cursor < 2;
    }

    double nextDouble()
    {
        return ++cursor + 0.5;
    }

    void remove()
    {
        assert(false);
    }
}

@("PrimitiveIterator.OfInt next and forEachRemaining read through nextInt")
unittest
{
    import std.exception : collectException;

    auto values = new Ints(4);
    PrimitiveIterator!(int, IntConsumer).OfInt iterator = values;
    Iterator!int boxed = iterator;
    assert(boxed.next() == 1);

    int sum;
    iterator.forEachRemaining(IntConsumer.of((int value) { sum = sum * 10 + value; }));
    assert(sum == 234);
    assert(values.availabilityChecks == 4);
    auto exhausted = collectException!NoSuchElementException(iterator.next());
    assert(exhausted !is null && exhausted.getMessage() == "end");

    // An exhausted iterator only asks once and never calls the action.
    iterator.forEachRemaining((int value) { assert(false); });
    assert(values.availabilityChecks == 5);
}

@("PrimitiveIterator forEachRemaining on the implementing class takes the consumer or a delegate")
unittest
{
    auto values = new Ints(3);
    int count;
    assert(values.nextInt() == 1);
    values.forEachRemaining((int value) { count += value; });
    assert(count == 5);

    auto more = new Ints(3);
    more.forEachRemaining(IntConsumer.of((int value) { count += value; }));
    assert(count == 11);
}

@("PrimitiveIterator forEachRemaining rejects a null action before taking an element")
unittest
{
    import std.exception : collectException;

    auto values = new Ints(2);
    PrimitiveIterator!(int, IntConsumer).OfInt iterator = values;
    assert(collectException!NullPointerException(iterator.forEachRemaining(cast(IntConsumer) null)) !is null);
    void delegate(int) @safe noAction;
    assert(collectException!NullPointerException(iterator.forEachRemaining(noAction)) !is null);
    assert(values.availabilityChecks == 0);
    assert(iterator.nextInt() == 1);

    PrimitiveIterator!(long, LongConsumer).OfLong longs = new Longs;
    assert(collectException!NullPointerException(longs.forEachRemaining(cast(LongConsumer) null)) !is null);
    PrimitiveIterator!(double, DoubleConsumer).OfDouble doubles = new Doubles;
    assert(collectException!NullPointerException(doubles.forEachRemaining(cast(DoubleConsumer) null)) !is null);
    assert(longs.next() == 10_000_000_000L && doubles.next() == 1.5);
}

@("PrimitiveIterator.OfLong and OfDouble forward every remaining value")
unittest
{
    long[] longs;
    PrimitiveIterator!(long, LongConsumer).OfLong a = new Longs;
    assert(a.nextLong() == 10_000_000_000L);
    a.forEachRemaining(LongConsumer.of((long value) { longs ~= value; }));
    assert(longs == [20_000_000_000L, 30_000_000_000L]);

    double[] doubles;
    PrimitiveIterator!(double, DoubleConsumer).OfDouble b = new Doubles;
    b.forEachRemaining((double value) { doubles ~= value; });
    assert(doubles == [1.5, 2.5]);
    assert(!b.hasNext());
}
