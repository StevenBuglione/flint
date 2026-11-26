module stream_flatmap_null_test;

import flint.java.util.stream : Stream;

@safe:

unittest
{
    int[] visited;
    auto flattened = Stream!int.of(1, 2, 3, 4).flatMap!int((int value) {
        visited ~= value;
        if (value == 1)
            return null;
        if (value == 2)
            return Stream!int.empty();
        return Stream!int.of(value * 10, value * 10 + 1);
    });
    assert(visited.length == 0);
    assert(flattened.findFirst().get() == 30);
    assert(visited == [1, 2, 3]);
}

unittest
{
    auto flattened = Stream!int.of(1, 2, 3, 4, 5).flatMap!int((int value) {
        if (value % 2 != 0)
            return null;
        return Stream!int.of(value, value + 1);
    });
    assert(flattened.toArray() == [2, 3, 4, 5]);
}
