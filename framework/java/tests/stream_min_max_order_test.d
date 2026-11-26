module stream_min_max_order_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util : Comparator;
import flint.java.util.stream : Stream;

@safe:

unittest
{
    foreach (maximum; [false, true])
    {
        int[2][] comparisons;
        auto comparator = Comparator!int.of((int left, int right) {
            comparisons ~= [left, right];
            const a = left % 10;
            const b = right % 10;
            return a < b ? int.min : a > b ? int.max : 0;
        });
        auto stream = Stream!int.of(11, 21, 12, 22);
        auto selected = maximum ? stream.max(comparator) : stream.min(comparator);
        assert(selected.get() == (maximum ? 12 : 11));
        const int[2][3] expected = [[11, 21], [11, 12], [maximum ? 12 : 11, 22]];
        assert(comparisons == expected, "comparison arguments are reversed");
    }
}

unittest
{
    foreach (maximum; [false, true])
    {
        int[] visited;
        auto stream = Stream!int.of(11, 21, 12, 22).peek((int value) { visited ~= value; });
        auto failure = new IllegalArgumentException("accumulated element first");
        auto reversedFailure = new IllegalArgumentException("new element first");
        auto comparator = Comparator!int.of((int left, int right) {
            if (left == 11 && right == 21)
                throw failure;
            if (left == 21 && right == 11)
                throw reversedFailure;
            return (left > right) - (left < right);
        });
        try
        {
            if (maximum)
                stream.max(comparator);
            else
                stream.min(comparator);
            assert(0, "missing comparator failure");
        }
        catch (IllegalArgumentException actual)
            assert(actual is failure);
        assert(visited == [11, 21]);
    }
}
