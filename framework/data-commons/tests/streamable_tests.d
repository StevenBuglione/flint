// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/util/StreamableUnitTests.java
// Copyright 2018-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module streamable_tests;

import flint.data.util : Streamable;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util.function_ : Function, Predicate, Supplier;
import flint.java.util.stream : Stream;
import std.exception : collectException;

@safe:

@("collectsToCollections")
unittest
{
    auto streamable = Streamable!int.of(() => Stream!int.of(1, 2, 1));
    auto list = streamable.toList();
    auto set = streamable.toSet();

    assert(list.toArray() == [1, 2, 1]);
    assert(set.size() == 2 && set.contains(1) && set.contains(2));
    assert(collectException!UnsupportedOperationException(list.add(3)) !is null);
    assert(collectException!UnsupportedOperationException(set.add(3)) !is null);
}

@("supplier creates a fresh stream for each use")
unittest
{
    int invocations;
    auto supplied = Supplier!(Stream!int).of(() { ++invocations; return Stream!int.of(3, 5); });
    auto streamable = Streamable!int.of(supplied);
    assert(invocations == 0);
    assert(streamable.get().toArray() == [3, 5]);
    assert(invocations == 1);

    auto iterator = streamable.iterator();
    assert(invocations == 2);
    assert(iterator.hasNext() && iterator.next() == 3);
    assert(iterator.hasNext() && iterator.next() == 5);
    assert(!iterator.hasNext());

    assert(!streamable.isEmpty() && invocations == 3);
    int seen;
    foreach (value; streamable)
    {
        seen = value;
        break;
    }
    assert(seen == 3 && invocations == 4);
}

@("varargs factories preserve order and duplicates")
unittest
{
    int[] supplied = [4, 2, 4];
    auto streamable = Streamable!int.of(supplied);
    supplied[0] = 9;
    int[] values;
    streamable.forEach((int value) { values ~= value; });
    assert(values == [4, 2, 4]);
    assert(streamable.stream().toArray() == [4, 2, 4]);
    assert(Streamable!int.of(4, 2, 4).stream().toArray() == values);
    assert(Streamable!int.empty().isEmpty());
    assert(Streamable!int.of().toList().isEmpty());
}

@("concatenatesVarargs")
unittest
{
    auto left = Streamable!int.of(1, 2);
    assert(left.and(3, 4).toList().toArray() == [1, 2, 3, 4]);

    int[] values = [3, 4];
    auto joined = left.and(values);
    values[0] = 9;
    assert(joined.toList().toArray() == [1, 2, 3, 4]);
}

@("concatenatesStreamable")
unittest
{
    auto joined = Streamable!int.of(1, 2).and(Streamable!int.of(3, 4));
    assert(joined.toList().toArray() == [1, 2, 3, 4]);
    assert(joined.stream().toArray() == [1, 2, 3, 4]);
}

@("concatenation obtains fresh streams without reading beyond a limit")
unittest
{
    int opens;
    int[] reads;
    auto supplier = Supplier!(Stream!int).of(() {
        ++opens;
        return Stream!int.of(3, 4).peek((int value) { reads ~= value; });
    });
    auto joined = Streamable!int.of(1, 2).and(supplier);
    assert(opens == 0 && reads.length == 0);
    assert(joined.stream().limit(1).toArray() == [1]);
    assert(opens == 1 && reads.length == 0);
    assert(joined.toList().toArray() == [1, 2, 3, 4]);
    assert(opens == 2 && reads == [3, 4]);
}

@("empty concatenation is distinct from null arguments")
unittest
{
    auto source = Streamable!int.of(1);
    assert(source.and().toList().toArray() == [1]);
    int[] owned = [7];
    assert(source.and(owned[0 .. 0]).toList().toArray() == [1]);

    alias IntStreams = Supplier!(Stream!int);
    alias IntFactory = Stream!int delegate() @safe;
    assert(collectException!IllegalArgumentException(source.and(cast(int[]) null)) !is null);
    assert(collectException!IllegalArgumentException(source.and(cast(IntStreams) null)) !is null);
    assert(collectException!IllegalArgumentException(source.and(cast(Streamable!int) null)) !is null);
    assert(collectException!IllegalArgumentException(source.and(cast(IntFactory) null)) !is null);
}

@("map applies either callable afresh and only to requested values")
unittest
{
    int opens;
    int[] visited;
    auto source = Streamable!int.of(() { ++opens; return Stream!int.of(1, 2); });
    auto mapper = Function!(int, string).of((int value) {
        visited ~= value;
        return value == 1 ? "one" : "two";
    });
    auto mapped = source.map(mapper);
    assert(opens == 0 && visited.length == 0);

    auto limited = mapped.stream().limit(1);
    assert(opens == 1 && visited.length == 0);
    assert(limited.toArray() == ["one"]);
    assert(visited == [1]);
    assert(mapped.toList().toArray() == ["one", "two"]);
    assert(opens == 2 && visited == [1, 1, 2]);
    assert(source.map((int value) => value * 2).toList().toArray() == [2, 4]);
}

@("flatMap drops null streams and starts fresh on repeat traversal")
unittest
{
    int[] visited;
    auto mapper = Function!(int, Stream!int).of((int value) {
        visited ~= value;
        return value == 2 ? null : Stream!int.of(value, -value);
    });
    auto source = Streamable!int.of(1, 2, 3);
    auto mapped = source.flatMap(mapper);
    assert(visited.length == 0);
    assert(mapped.stream().limit(1).toArray() == [1]);
    assert(visited == [1]);
    assert(mapped.toList().toArray() == [1, -1, 3, -3]);
    assert(visited == [1, 1, 2, 3]);
    assert(source.flatMap((int value) => Stream!int.of(value)).toList().toArray() == [1, 2, 3]);
}

@("filter short-circuits and repeats the predicate for each traversal")
unittest
{
    int[] visited;
    auto predicate = Predicate!int.of((int value) { visited ~= value; return value % 2 == 0; });
    auto source = Streamable!int.of(1, 2, 3, 4);
    auto filtered = source.filter(predicate);
    assert(visited.length == 0);
    assert(filtered.stream().limit(1).toArray() == [2]);
    assert(visited == [1, 2]);
    assert(filtered.toList().toArray() == [2, 4]);
    assert(visited == [1, 2, 1, 2, 3, 4]);
    assert(source.filter((int value) => value > 2).toList().toArray() == [3, 4]);
}

@("transform factories reject null callables before opening a stream")
unittest
{
    alias Mapper = int delegate(int) @safe;
    alias FlatMapper = Stream!int delegate(int) @safe;
    alias Filter = bool delegate(int) @safe;
    int opens;
    auto source = Streamable!int.of(() { ++opens; return Stream!int.empty(); });
    assert(collectException!IllegalArgumentException(source.map(cast(Function!(int, int)) null)) !is null);
    assert(collectException!IllegalArgumentException(source.map(cast(Mapper) null)) !is null);
    assert(collectException!IllegalArgumentException(source.flatMap(cast(Function!(int, Stream!int)) null)) !is null);
    assert(collectException!IllegalArgumentException(source.flatMap(cast(FlatMapper) null)) !is null);
    assert(collectException!IllegalArgumentException(source.filter(cast(Predicate!int) null)) !is null);
    assert(collectException!IllegalArgumentException(source.filter(cast(Filter) null)) !is null);
    assert(opens == 0);
}
