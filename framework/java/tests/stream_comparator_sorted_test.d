module stream_comparator_sorted_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException;
import flint.java.util : Comparator, Iterator;
import flint.java.util.stream : Stream;

@safe:

private int byTens(int left, int right)
{
    return (left / 10 > right / 10) - (left / 10 < right / 10);
}

unittest
{
    int visited, comparisons;
    auto order = Comparator!int.of((int left, int right) { ++comparisons; return byTens(left, right); });
    auto source = Stream!int.of(21, 11, 22, 12).peek((int) { ++visited; });
    auto sorted = source.sorted(order);
    assert(visited == 0 && comparisons == 0, "comparator sorting eagerly traversed its source");
    try
    {
        source.findFirst();
        assert(0, "the source must be linked when sorted is added");
    }
    catch (IllegalStateException)
    {
    }
    auto iterator = sorted.iterator();
    assert(visited == 0 && comparisons == 0);
    assert(iterator.next() == 11 && visited == 4 && comparisons > 0);
    assert(iterator.next() == 12 && iterator.next() == 21 && iterator.next() == 22);
    assert(!iterator.hasNext());
}

unittest
{
    // Temurin 21.0.13+9 takes the upstream before rejecting a null comparator.
    int visited;
    auto fresh = Stream!int.of(2, 1).peek((int) { ++visited; });
    try
    {
        fresh.sorted(cast(Comparator!int) null);
        assert(0, "missing NullPointerException for a null comparator");
    }
    catch (NullPointerException)
    {
    }
    try
    {
        fresh.findFirst();
        assert(0, "a null comparator must still link its source");
    }
    catch (IllegalStateException)
    {
    }
    assert(visited == 0);

    auto spent = Stream!int.of(2, 1);
    spent.findFirst();
    try
    {
        spent.sorted(cast(Comparator!int) null);
        assert(0, "a spent source must report IllegalStateException first");
    }
    catch (IllegalStateException)
    {
    }
}

unittest
{
    // A comparator-sorted stage is derived: forEach rejects a null action before taking it.
    auto sorted = Stream!int.of(2, 1).sorted(Comparator!int.of((int left, int right) => left - right));
    try
    {
        sorted.forEach(null);
        assert(0, "missing NullPointerException for a null action");
    }
    catch (NullPointerException)
    {
    }
    assert(sorted.findFirst().get() == 1);
}

unittest
{
    auto failure = new IllegalArgumentException("comparison failed");
    auto sorted = Stream!int.of(2, 1).sorted(Comparator!int.of((int left, int right) {
            if (left != right)
                throw failure;
            return 0;
        }));
    Iterator!int iterator = sorted.iterator();
    try
    {
        iterator.hasNext();
        assert(0, "missing comparator failure");
    }
    catch (IllegalArgumentException actual)
        assert(actual is failure);
}
