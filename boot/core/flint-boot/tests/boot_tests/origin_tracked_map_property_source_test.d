// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/env/
// OriginTrackedMapPropertySourceTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the source holds origin-tracked strings, so a non-tracked value is one tracked to no
// origin; the map is filled before the source is created over it; Mockito's Origin is a test origin.
module boot_tests.origin_tracked_map_property_source_test;

import flint.boot.env : OriginTrackedMapPropertySource;
import flint.boot.origin : Origin, OriginTrackedValue;

@safe:

/// The mocked `Origin`.
private final class TestOrigin : Origin
{
    Origin getParent()
    {
        return null;
    }

    override string toString() const
    {
        return "test origin";
    }
}

private OriginTrackedMapPropertySource source(OriginTrackedValue[string] map)
{
    return new OriginTrackedMapPropertySource("test", map.keys, map);
}

@("getPropertyWhenMissingShouldReturnNull") unittest
{
    assert(source(null).getProperty("test") is null);
}

@("getPropertyWhenNonTrackedShouldReturnValue") unittest
{
    assert(source(["test": OriginTrackedValue.of("foo")]).getProperty("test") == "foo");
}

@("getPropertyWhenTrackedShouldReturnValue") unittest
{
    assert(source(["test": OriginTrackedValue.of("foo", new TestOrigin)]).getProperty("test") == "foo");
}

@("getPropertyOriginWhenMissingShouldReturnNull") unittest
{
    assert(source(null).getOrigin("test") is null);
}

@("getPropertyOriginWhenNonTrackedShouldReturnNull") unittest
{
    assert(source(["test": OriginTrackedValue.of("foo")]).getOrigin("test") is null);
}

@("getPropertyOriginWhenTrackedShouldReturnOrigin") unittest
{
    auto origin = new TestOrigin;
    assert(source(["test": OriginTrackedValue.of("foo", origin)]).getOrigin("test") is origin);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
