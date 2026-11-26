// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/util/StreamableUnitTests.java
// Copyright 2018-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module streamable_tests;

import flint.data.util : Streamable;
import flint.java.lang : UnsupportedOperationException;
import flint.java.util.function_ : Supplier;
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
