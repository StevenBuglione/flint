module stream_natural_sorted_test;

import flint.java.lang : Comparable, IllegalArgumentException, IllegalStateException;
import flint.java.util : Iterator;
import flint.java.util.stream : Stream;

@safe:

private final class Ranked : Comparable!Ranked
{
    private int rank;
    private IllegalArgumentException failure;

    this(int rank, IllegalArgumentException failure = null)
    {
        this.rank = rank;
        this.failure = failure;
    }

    int compareTo(Ranked other)
    {
        if (failure !is null)
            throw failure;
        return (rank > other.rank) - (rank < other.rank);
    }
}

unittest
{
    int visited;
    auto firstTie = new Ranked(1);
    auto secondTie = new Ranked(1);
    auto high = new Ranked(3);
    auto source = Stream!Ranked.of(high, firstTie, secondTie).peek((Ranked) { ++visited; });
    auto sorted = source.sorted();
    assert(visited == 0, "natural sorting eagerly traversed its source");
    try
    {
        source.findFirst();
        assert(0, "the source must be linked when sorted is added");
    }
    catch (IllegalStateException)
    {
    }
    auto iterator = sorted.iterator();
    assert(visited == 0);
    assert(iterator.next() is firstTie && visited == 3);
    assert(iterator.next() is secondTie);
    assert(iterator.next() is high && !iterator.hasNext());
}

unittest
{
    auto failure = new IllegalArgumentException("natural comparison failed");
    auto first = new Ranked(2, failure);
    auto second = new Ranked(1, failure);
    auto sorted = Stream!Ranked.of(first, second).sorted();
    Iterator!Ranked iterator = sorted.iterator();
    try
    {
        iterator.hasNext();
        assert(0, "missing natural comparison failure");
    }
    catch (IllegalArgumentException actual)
        assert(actual is failure);
    assert(!iterator.hasNext());
}

private Stream!int sortWithBorrowedComparator(scope int delegate(int, int) @safe compare)
{
    return Stream!int.of(3, 1, 2).sorted(compare);
}

unittest
{
    int comparisons;
    auto sorted = sortWithBorrowedComparator((int left, int right) {
        ++comparisons;
        return (left > right) - (left < right);
    });
    assert(comparisons > 0);
    assert(sorted.toArray() == [1, 2, 3]);
}
