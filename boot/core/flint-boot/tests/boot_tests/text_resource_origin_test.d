// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/origin/
// TextResourceOriginTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: a resource is its description (`ClassPathResource.getDescription()`); a location
// is a struct, so where upstream passes a null location it does not look at, the origin is at 0:0.
// Not ported: toStringWhenResourceIsClasspathResourceReturnsToStringWithJar (Java jar URIs).
module boot_tests.text_resource_origin_test;

import flint.boot.origin : TextResourceOrigin;
import flint.core.io : ClassPathResource;

@safe:

alias Location = TextResourceOrigin.Location;

private string fooTxt()
{
    return new ClassPathResource("foo.txt").getDescription();
}

@("createWithNullResourceSetsNullResource") unittest
{
    auto origin = new TextResourceOrigin(null, Location(0, 0));
    assert(origin.getResource() is null);
}

@("getResourceReturnResource") unittest
{
    auto origin = new TextResourceOrigin(fooTxt(), Location(0, 0));
    assert(origin.getResource() == fooTxt());
}

@("getLocationReturnsLocation") unittest
{
    const location = Location(1, 2);
    auto origin = new TextResourceOrigin(null, location);
    assert(origin.getLocation() == location);
}

@("getParentWhenResourceIsNotOriginTrackedReturnsNull") unittest
{
    auto origin = new TextResourceOrigin(fooTxt(), Location(0, 0));
    assert(origin.getParent() is null);
}

@("getLocationLineReturnsLine") unittest
{
    const location = Location(1, 2);
    assert(location.getLine() == 1);
}

@("getLocationColumnReturnsColumn") unittest
{
    const location = Location(1, 2);
    assert(location.getColumn() == 2);
}

@("locationToStringReturnsNiceString") unittest
{
    const location = Location(1, 2);
    assert(location.toString() == "2:3");
}

@("toStringReturnsNiceString") unittest
{
    auto origin = new TextResourceOrigin(fooTxt(), Location(1, 2));
    assert(origin.toString() == "class path resource [foo.txt] - 2:3", origin.toString());
}

@("toStringWhenResourceIsNullReturnsNiceString") unittest
{
    auto origin = new TextResourceOrigin(null, Location(1, 2));
    assert(origin.toString() == "unknown resource [?] - 2:3");
}

@("locationEqualsAndHashCodeUsesLineAndColumn") unittest
{
    const location1 = Location(1, 2);
    const location2 = Location(1, 2);
    const location3 = Location(2, 2);
    assert(hashOf(location1) == hashOf(location1));
    assert(hashOf(location1) == hashOf(location2));
    assert(hashOf(location1) != hashOf(location3));
    assert(location1 == location1);
    assert(location1 == location2);
    assert(location1 != location3);
}

version (FlintTextResourceOriginApi)
{
    // Gap: an origin always has a location, and a resource (a description) cannot carry the origin it came from.
    @("createWithNullLocationSetsNullLocation") unittest
    {
        auto origin = new TextResourceOrigin(null);
        assert(origin.getLocation() is null);
    }

    @("getParentWhenResourceIsOriginTrackedReturnsResourceOrigin") unittest
    {
        import flint.boot.origin : Origin, OriginTrackedResource;

        final class MockOrigin : Origin
        {
            Origin getParent()
            {
                return null;
            }

            override string toString() const
            {
                return "test";
            }
        }

        auto resourceOrigin = new MockOrigin;
        auto resource = OriginTrackedResource.of(new ClassPathResource("foo.txt"), resourceOrigin);
        auto origin = new TextResourceOrigin(resource, null);
        assert(origin.getParent() is resourceOrigin);
    }

    @("toStringWhenLocationIsNullReturnsNiceString") unittest
    {
        auto origin = new TextResourceOrigin(fooTxt());
        assert(origin.toString() == "class path resource [foo.txt]");
    }
}

version (FlintOriginEquality)
{
    // Gap: origins and tracked values compare by identity, not by value.
    /// Java's `equals`: D's `==` on class objects goes through `Object.opEquals`, which is `@system`.
    private bool equal(Object a, Object b) @trusted
    {
        // SAFETY: the operands are live test objects; opEquals only compares their fields.
        return a == b;
    }

    @("equalsAndHashCodeUsesResourceAndLocation") unittest
    {
        auto origin1 = new TextResourceOrigin(fooTxt(), Location(1, 2));
        auto origin2 = new TextResourceOrigin(fooTxt(), Location(1, 2));
        auto origin3 = new TextResourceOrigin(fooTxt(), Location(2, 2));
        auto origin4 = new TextResourceOrigin(new ClassPathResource("foo2.txt").getDescription(), Location(1, 2));
        assert(origin1.toHash() == origin1.toHash());
        assert(origin1.toHash() == origin2.toHash());
        assert(origin1.toHash() != origin3.toHash());
        assert(origin1.toHash() != origin4.toHash());
        assert(equal(origin1, origin1));
        assert(equal(origin1, origin2));
        assert(!equal(origin1, origin3));
        assert(!equal(origin1, origin4));
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
