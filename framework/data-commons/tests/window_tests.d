// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/WindowUnitTests.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module window_tests;

import flint.data.domain : OffsetScrollPosition, ScrollPosition, Window;
import flint.java.lang : IllegalStateException, IndexOutOfBoundsException;
import flint.java.util : ArrayList, List, NoSuchElementException, Objects;

@safe:

@("equalsAndHashCode")
unittest
{
    auto positions = OffsetScrollPosition.positionFunction(0);
    auto one = Window!int.from(List!int.of(1, 2, 3), positions);
    auto two = Window!int.from(List!int.of(1, 2, 3), positions);
    auto continued = Window!int.from(List!int.of(1, 2, 3), positions, true);
    assert(Objects.equals(one, two));
    assert(Objects.hashCode(one) == Objects.hashCode(two));
    assert(!Objects.equals(continued, two));
    assert(Objects.hashCode(continued) != Objects.hashCode(two));
}

@("allowsIteration")
unittest
{
    auto window = Window!int.from(List!int.of(1, 2, 3), OffsetScrollPosition.positionFunction(0));
    int[] seen;
    foreach (value; window)
        seen ~= value;
    assert(seen == [1, 2, 3]);
}

@("shouldCreateCorrectPositions")
unittest
{
    auto window = Window!int.from(List!int.of(1, 2, 3), OffsetScrollPosition.positionFunction(0));
    assert(Objects.equals(window.positionAt(0), ScrollPosition.offset(0)));
    assert(Objects.equals(window.positionAt(window.size() - 1), ScrollPosition.offset(2)));
    assert(Objects.equals(window.positionAt(1), ScrollPosition.offset(1)));
    assert(Objects.equals(window.positionAt!int(1), ScrollPosition.offset(0)));
}

@("A mapped window retains positions and continuation")
unittest
{
    auto items = new ArrayList!string(["one", "second"]);
    auto source = Window!string.from(items, (int index) => ScrollPosition.offset(4 + index), true);
    auto mapped = source.map((string item) => item.length);
    assert(mapped.getContent().toArray() == [3, 6]);
    assert(mapped.hasNext() && !mapped.isLast());
    assert(Objects.equals(mapped.positionAt(1), ScrollPosition.offset(5)));
    assert(Objects.equals(source.positionAt("second"), ScrollPosition.offset(5)));

    items.add("third");
    assert(source.size() == 3 && mapped.size() == 2);
}

@("Position availability distinguishes invalid indexes from unavailable positions")
unittest
{
    import std.exception : assertThrown;

    auto window = Window!string.from(List!string.of("missing"), delegate ScrollPosition(int) @safe {
        throw new IllegalStateException("No cursor for this row");
    });
    assert(!window.hasPosition(0));
    assertThrown!IndexOutOfBoundsException(window.hasPosition(1));
    assertThrown!NoSuchElementException(window.positionAt("absent"));
}

@("Offset position functions with equal starts keep windows equal")
unittest
{
    auto items = List!string.of("first");
    auto one = Window!string.from(items, OffsetScrollPosition.positionFunction(3));
    auto two = Window!string.from(items, OffsetScrollPosition.positionFunction(3));
    auto different = Window!string.from(items, OffsetScrollPosition.positionFunction(4));
    assert(Objects.equals(one, two));
    assert(Objects.hashCode(one) == Objects.hashCode(two));
    assert(!Objects.equals(one, different));
}

@("Non-int numeric elements select the item overload")
unittest
{
    auto positions = OffsetScrollPosition.positionFunction(7);
    auto shorts = Window!short.from(List!short.of(4, 5), positions);
    auto longs = Window!long.from(List!long.of(4, 5), positions);
    assert(Objects.equals(shorts.positionAt(cast(short) 4), ScrollPosition.offset(7)));
    assert(Objects.equals(longs.positionAt(5L), ScrollPosition.offset(8)));
    assert(Objects.equals(shorts.positionAt(1), ScrollPosition.offset(8)));
    assert(Objects.equals(longs.positionAt(0), ScrollPosition.offset(7)));
}
