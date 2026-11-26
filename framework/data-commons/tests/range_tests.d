// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/RangeUnitTests.java
// Copyright 2015-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module range_tests;

import flint.data.domain : Range;
import flint.java.lang : IllegalArgumentException, Long;
import flint.java.util : Comparator, Objects;
import std.exception : assertThrown;

@safe:

private alias LongRange = Range!long;
private alias LongBound = LongRange.Bound;

private void assertMembership(LongRange range, scope const(long)[] values, scope const(bool)[] expected)
{
    assert(values.length == expected.length);
    int delegate(long, long) @safe compare = (long first, long second) => Long.compare(first, second);
    foreach (i, value; values)
    {
        assert(range.contains(value) == expected[i]);
        assert(range.contains(value, compare) == expected[i]);
    }
}

@("rejectsNullReferenceValuesForContains")
unittest
{
    auto range = Range!string.closed("a", "z");
    assertThrown!IllegalArgumentException(range.contains(null));
}

@("excludesLowerBoundIfConfigured")
unittest
{
    auto range = LongRange.from(LongBound.exclusive(10)).to(LongBound.inclusive(20));
    assertMembership(range, [10, 20, 15, 5, 25], [false, true, true, false, false]);
}

@("excludesUpperBoundIfConfigured")
unittest
{
    auto range = LongRange.of(LongBound.inclusive(10), LongBound.exclusive(20));
    assertMembership(range, [10, 20, 15, 5, 25], [true, false, true, false, false]);
}

@("handlesOpenUpperBoundCorrectly")
unittest
{
    auto range = LongRange.of(LongBound.inclusive(10), LongBound.unbounded());
    assertMembership(range, [10, 20, 15, 5, 25], [true, true, true, false, true]);
    assert(range.getLowerBound().isBounded());
    assert(!range.getUpperBound().isBounded());
    assert(range.toString() == "[10-unbounded");
}

@("handlesOpenLowerBoundCorrectly")
unittest
{
    auto range = LongRange.of(LongBound.unbounded(), LongBound.inclusive(20));
    assertMembership(range, [10, 20, 15, 5, 25], [true, true, true, true, false]);
    assert(!range.getLowerBound().isBounded());
    assert(range.getUpperBound().isBounded());
}

@("createsInclusiveBoundaryCorrectly")
unittest
{
    auto bound = Range!int.Bound.inclusive(10);
    assert(bound.isInclusive());
    assert(bound.getValue().get() == 10);
}

@("createsExclusiveBoundaryCorrectly")
unittest
{
    auto bound = Range!double.Bound.exclusive(10.0);
    assert(!bound.isInclusive());
    assert(bound.getValue().get() == 10.0);
}

@("createsRangeFromBoundariesCorrectly")
unittest
{
    auto lower = LongBound.inclusive(10);
    auto upper = LongBound.inclusive(20);
    auto range = LongRange.of(lower, upper);
    assertMembership(range, [9, 10, 20, 21], [false, true, true, false]);
}

@("shouldExclusiveBuildRangeLowerFirst")
unittest
{
    auto range = LongRange.from(LongBound.exclusive(10)).to(LongBound.exclusive(20));
    assertMembership(range, [9, 10, 11, 19, 20, 21], [false, false, true, true, false, false]);
    assert(range.toString() == "(10-20)");
}

@("shouldBuildRange")
unittest
{
    auto range = LongRange.from(LongBound.inclusive(10)).to(LongBound.inclusive(20));
    assertMembership(range, [9, 10, 11, 19, 20, 21], [false, true, true, true, true, false]);
    assert(range.toString() == "[10-20]");
}

@("createsUnboundedRange")
unittest
{
    auto range = LongRange.unbounded();
    assertMembership(range, [10], [true]);
    assert(range.getLowerBound().getValue().isEmpty());
    assert(range.getUpperBound().getValue().isEmpty());
}

@("createsOpenRange")
unittest
{
    assertMembership(LongRange.open(5, 10), [5, 10], [false, false]);
}

@("createsClosedRange")
unittest
{
    assertMembership(LongRange.closed(5, 10), [5, 10], [true, true]);
}

@("createsLeftOpenRange")
unittest
{
    assertMembership(LongRange.leftOpen(5, 10), [5, 10], [false, true]);
}

@("createsRightOpenRange")
unittest
{
    assertMembership(LongRange.rightOpen(5, 10), [5, 10], [true, false]);
}

@("mapsBoundaryValues")
unittest
{
    auto range = LongRange.leftOpen(5, 10).map((long item) => item * 10);
    assert(Objects.equals(range.getLowerBound(), LongBound.exclusive(50)));
    assert(Objects.equals(range.getUpperBound(), LongBound.inclusive(100)));

    auto unbounded = LongRange.leftOpen(5, 10).map((long) => cast(string) null);
    assert(Objects.equals(unbounded, Range!string.unbounded()));
}

@("createsLeftUnboundedRange")
unittest
{
    assert(LongRange.leftUnbounded(LongBound.inclusive(10)).contains(-10_000));
}

@("createsRightUnboundedRange")
unittest
{
    assert(LongRange.rightUnbounded(LongBound.inclusive(10)).contains(10_000));
}

@("createsSingleValueRange")
unittest
{
    auto range = LongRange.just(10);
    assert(range.contains(10));
    assert(!range.contains(11));
}

@("Comparator order and invocation are preserved")
unittest
{
    int calls;
    auto descending = Comparator!long.of((long first, long second) {
        ++calls;
        return Long.compare(second, first);
    });
    auto range = LongRange.closed(20, 10);
    assert(range.contains(15, descending));
    assert(calls == 2);
    assert(!range.contains(30, descending));
    assert(calls == 4);
}

@("Unbounded factories have value equality")
unittest
{
    auto one = LongRange.unbounded();
    auto two = LongRange.unbounded();
    assert(!one.getLowerBound().isBounded() && !one.getUpperBound().isBounded());
    assert(one.getLowerBound().equals(LongBound.unbounded()));
    assert(one.equals(two));
    assert(one.hashCode() == two.hashCode());
    assert(!one.equals(LongRange.open(0, 1)));
}

@("Floating endpoints follow Java NaN and signed-zero ordering")
unittest
{
    alias DoubleRange = Range!double;
    auto finite = DoubleRange.closed(-1.0, 1.0);
    assert(!finite.contains(double.nan));
    assert(DoubleRange.just(double.nan).contains(double.nan));
    assert(!DoubleRange.just(double.nan).contains(0.0));
    assert(!DoubleRange.just(-0.0).contains(0.0));

    auto nan = DoubleRange.Bound.inclusive(double.nan);
    assert(Objects.equals(nan, DoubleRange.Bound.inclusive(-double.nan)));
    assert(!Objects.equals(DoubleRange.Bound.inclusive(-0.0), DoubleRange.Bound.inclusive(0.0)));
}

@("Range equality follows the endpoints across generic arguments")
unittest
{
    static class Animal
    {
    }

    static class Dog : Animal
    {
    }

    assert(LongRange.unbounded().equals(Range!string.unbounded()));
    auto dog = new Dog();
    auto specific = Range!Dog.just(dog);
    auto general = Range!Animal.just(dog);
    assert(specific.equals(general) && general.equals(specific));
    assert(specific.hashCode() == general.hashCode());
    assert(!LongRange.just(1).equals(Range!int.just(1)));
}
