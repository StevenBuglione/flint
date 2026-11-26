// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/WindowIteratorUnitTests.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module window_iterator_tests;

import flint.data.domain : KeysetScrollPosition, OffsetScrollPosition, ScrollPosition, Window;
import flint.data.support : WindowIterator;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util : List, Map, NoSuchElementException, Objects;
import flint.java.util.function_ : Function;
import std.exception : assertThrown;

@safe:

private Window!string windowOf(List!string items, long start = 0, bool more = false)
{
    return Window!string.from(items, OffsetScrollPosition.positionFunction(start), more);
}

@("loadsDataOnNext")
unittest
{
    int calls;
    auto query = Function!(ScrollPosition, Window!string).of((ScrollPosition position) {
        ++calls;
        assert(position.isInitial());
        return windowOf(List!string.of());
    });
    auto iterator = WindowIterator!string.of(query).startingAt(ScrollPosition.offset());
    assert(calls == 0);
    assert(!iterator.hasNext());
    assert(calls == 1);
}

@("hasNextReturnsFalseIfNoDataAvailable")
unittest
{
    auto window = windowOf(List!string.of());
    auto iterator = WindowIterator!string.of((ScrollPosition) => window).startingAt(ScrollPosition.offset());
    assert(!iterator.hasNext());
}

@("nextThrowsExceptionIfNoElementAvailable")
unittest
{
    auto window = windowOf(List!string.of());
    auto iterator = WindowIterator!string.of((ScrollPosition) => window).startingAt(ScrollPosition.offset());
    assertThrown!NoSuchElementException(iterator.next());
}

@("hasNextReturnsTrueIfDataAvailableButOnlyOnePage")
unittest
{
    auto window = windowOf(List!string.of("a", "b"));
    auto iterator = WindowIterator!string.of((ScrollPosition) => window).startingAt(ScrollPosition.offset());
    assert(iterator.hasNext());
    assert(iterator.next() == "a");
    assert(iterator.hasNext());
    assert(iterator.next() == "b");
    assert(!iterator.hasNext());
    assert(!iterator.hasNext());
}

@("hasNextReturnsCorrectlyIfNextPageIsEmpty")
unittest
{
    auto window = windowOf(List!string.of("a", "b"), 0, true);
    auto empty = windowOf(List!string.of());
    auto iterator = WindowIterator!string.of((ScrollPosition position) => position.isInitial()
            ? window : empty).startingAt(ScrollPosition.offset());
    assert(iterator.hasNext());
    assert(iterator.next() == "a");
    assert(iterator.hasNext());
    assert(iterator.next() == "b");
    assert(!iterator.hasNext());
    assert(!iterator.hasNext());
}

@("allowsToIterateAllWindows")
unittest
{
    auto initial = windowOf(List!string.of("a", "b"), 0, true);
    auto terminal = windowOf(List!string.of("c", "d"), 2);
    auto iterator = WindowIterator!string.of((ScrollPosition position) {
        if (position.isInitial())
            return initial;
        assert(Objects.equals(position, ScrollPosition.offset(1)));
        return terminal;
    }).startingAt(ScrollPosition.offset());

    string[] seen;
    while (iterator.hasNext())
        seen ~= iterator.next();
    assert(seen == ["a", "b", "c", "d"]);
}

private ScrollPosition backwardPosition(int value)
{
    return ScrollPosition.backward(Map!(string, Any).of("k", Any.of(value)));
}

@("considersBackwardKeysetScrolling")
unittest
{
    auto initial = Window!string.from(List!string.of("c", "d"), (int index) => backwardPosition(10 + index), true);
    auto terminal = Window!string.from(List!string.of("a", "b"), (int index) => backwardPosition(index));
    auto iterator = WindowIterator!string.of((ScrollPosition position) {
        if (position.isInitial())
            return initial;
        auto keyset = cast(KeysetScrollPosition) position;
        assert(keyset.scrollsBackward() && keyset.getKeys().get("k").get!int() == 10);
        return terminal;
    }).startingAt(ScrollPosition.keyset().backward());

    string[] seen;
    while (iterator.hasNext())
        seen ~= iterator.next();
    assert(seen == ["d", "c", "b", "a"]);
}

@("Scroll iterators start from a position and reject removal")
unittest
{
    auto window = windowOf(List!string.of("a"));
    auto builder = WindowIterator!string.of((ScrollPosition) => window);
    assertThrown!IllegalArgumentException(builder.startingAt(null));
    auto iterator = builder.startingAt(ScrollPosition.offset());
    assert(iterator.next() == "a");
    assertThrown!UnsupportedOperationException(iterator.remove());
}
