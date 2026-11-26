// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/ScrollPositionUnitTests.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.scroll_position_tests;

import flint.data.domain : KeysetScrollPosition, OffsetScrollPosition, Pageable, PageRequest, ScrollPosition;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IllegalStateException, IndexOutOfBoundsException,
    UnsupportedOperationException;
import flint.java.util : Collections, LinkedHashMap, Map;
import std.exception : assertThrown;

@safe:

private alias Keys = Map!(string, Any);
private alias Direction = ScrollPosition.Direction;

private Keys sampleKeys()
{
    auto keys = new LinkedHashMap!(string, Any);
    keys.put("k", Any.of("v"));
    return keys;
}

@("equalsAndHashCodeForKeysets")
unittest
{
    auto keys = sampleKeys();
    auto first = ScrollPosition.forward(keys);
    auto second = ScrollPosition.forward(keys);
    auto backward = ScrollPosition.backward(keys);

    assert(first == second && first.hashCode() == second.hashCode());
    assert(first != backward && first.hashCode() != backward.hashCode());
}

@("equalsAndHashCodeForOffsets")
unittest
{
    auto first = ScrollPosition.offset(1);
    auto second = ScrollPosition.offset(1);
    auto other = ScrollPosition.offset(2);

    assert(first == second && first.hashCode() == second.hashCode());
    assert(first != other && first.hashCode() != other.hashCode());
}

@("shouldCreateCorrectIndexPosition")
unittest
{
    auto zero = OffsetScrollPosition.positionFunction(0);
    assert(zero.apply(0) == ScrollPosition.offset(0));
    assert(zero.apply(1) == ScrollPosition.offset(1));

    auto hundred = OffsetScrollPosition.positionFunction(100);
    assert(hundred.apply(0) == ScrollPosition.offset(100));
    assert(hundred.apply(1) == ScrollPosition.offset(101));
}

@("rejectsNegativeOffset")
unittest
{
    assertThrown!IllegalArgumentException(ScrollPosition.offset(-1));
}

@("advanceOffsetBelowZeroCapsAtZero")
unittest
{
    auto offset = ScrollPosition.offset(5);
    assert(offset.getOffset() == 5);
    assert(offset.advanceBy(-10) == ScrollPosition.offset(0));
}

@("advanceOffsetForward")
unittest
{
    auto offset = ScrollPosition.offset(5);
    assert(offset.getOffset() == 5);
    assert(offset.advanceBy(5) == ScrollPosition.offset(10));
}

@("advanceInitialOffsetForward")
unittest
{
    assert(ScrollPosition.offset().advanceBy(5) == ScrollPosition.offset(5));
}

@("setsUpForwardScrolling")
unittest
{
    auto keys = sampleKeys();
    auto position = ScrollPosition.forward(keys);
    assert(position.getKeys().equals(cast(Object) keys));
    assert(position.getDirection() == Direction.FORWARD);
    assert(position.scrollsForward() && !position.scrollsBackward());

    auto backward = position.backward();
    assert(backward.getKeys().equals(cast(Object) keys));
    assert(backward.getDirection() == Direction.BACKWARD);
    assert(backward.scrollsBackward() && !backward.scrollsForward());
    assert(position.reverse() == backward);
}

@("setsUpBackwardScrolling")
unittest
{
    auto keys = sampleKeys();
    auto position = ScrollPosition.backward(keys);
    assert(position.getKeys().equals(cast(Object) keys));
    assert(position.getDirection() == Direction.BACKWARD);
    assert(position.scrollsBackward() && !position.scrollsForward());

    auto forward = position.forward();
    assert(forward.getKeys().equals(cast(Object) keys));
    assert(forward.getDirection() == Direction.FORWARD);
    assert(forward.scrollsForward() && !forward.scrollsBackward());
    assert(position.reverse() == forward);
}

@("initialOffsetPosition")
unittest
{
    auto position = ScrollPosition.offset();
    assert(position.isInitial());
    assertThrown!IllegalStateException(position.getOffset());
}

@("initialOffsetPositionIsNotEqualToPositionOfFirstElement")
unittest
{
    auto first = ScrollPosition.offset(0);
    assert(!first.isInitial());
    assert(first != ScrollPosition.offset());
}

@("initialKeysetPosition")
unittest
{
    auto position = ScrollPosition.keyset();
    assert(position.isInitial() && position.scrollsForward());

    auto empty = Collections.emptyMap!(string, Any)();
    position = ScrollPosition.of(empty, Direction.FORWARD);
    assert(position.isInitial() && position.scrollsForward() && !position.scrollsBackward());

    position = ScrollPosition.of(empty, Direction.BACKWARD);
    assert(position.isInitial() && position.scrollsBackward() && !position.scrollsForward());
}

@("AbstractPageRequestUnitTests.createsOffsetScrollPosition")
unittest
{
    assert(PageRequest.of(0, 10).toScrollPosition().isInitial());
    assert(PageRequest.of(1, 10).toScrollPosition().getOffset() == 9);
}

@("Pageable scrolling rejects unpaged and retains offsets wider than int")
unittest
{
    assertThrown!IllegalStateException(Pageable.unpaged().toScrollPosition());
    auto position = PageRequest.of(int.max, 2).toScrollPosition();
    assert(position.getOffset() == 2L * int.max - 1);
}

@("Position functions start after the current offset")
unittest
{
    assert(ScrollPosition.offset().positionFunction().apply(0).getOffset() == 0);
    auto next = ScrollPosition.offset(4).positionFunction();
    assert(next.apply(0).getOffset() == 5);
    assertThrown!IndexOutOfBoundsException(next.apply(-1));
    assertThrown!IllegalArgumentException(OffsetScrollPosition.positionFunction(-1));
}

@("Keyset positions own a read-only snapshot of the keys")
unittest
{
    auto keys = sampleKeys();
    auto position = ScrollPosition.forward(keys);
    keys.put("k", Any.of("changed"));
    assert(position.getKeys().get("k").get!string() == "v");
    assertThrown!UnsupportedOperationException(position.getKeys().put("k", Any.of("changed")));
    assertThrown!IllegalArgumentException(ScrollPosition.forward(null));
}
