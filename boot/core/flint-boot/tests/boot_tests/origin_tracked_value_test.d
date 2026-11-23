// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/origin/
// OriginTrackedValueTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: tracked values are strings, the only kind the loaders produce, so `new Object()`
// is a distinct string; Mockito's Origin is a test origin.
// Not ported: ofWhenValueIsCharSequenceShouldReturnCharSequence (Java's CharSequence; the value is a D string).
module boot_tests.origin_tracked_value_test;

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

@("getValueShouldReturnValue") unittest
{
    const value = "value";
    assert(OriginTrackedValue.of(value).getValue() == value);
}

@("getOriginShouldReturnOrigin") unittest
{
    const value = "value";
    auto origin = new TestOrigin;
    assert(OriginTrackedValue.of(value, origin).getOrigin() is origin);
}

@("toStringShouldReturnValueToString") unittest
{
    const value = "value";
    assert(OriginTrackedValue.of(value).toString() == value);
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

    @("hashCodeAndEqualsShouldIgnoreOrigin") unittest
    {
        const value1 = "value1";
        auto tracked1 = OriginTrackedValue.of(value1);
        auto tracked2 = OriginTrackedValue.of(value1, new TestOrigin);
        auto tracked3 = OriginTrackedValue.of("value3");
        assert(tracked1.toHash() == tracked2.toHash());
        assert(equal(tracked1, tracked1));
        assert(equal(tracked1, tracked2));
        assert(!equal(tracked1, tracked3));
    }
}

version (FlintOriginTrackedValueNull)
{
    // Gap: a null value is tracked instead of `of` returning null.
    @("ofWhenValueIsNullShouldReturnNull") unittest
    {
        assert(OriginTrackedValue.of(null) is null);
        assert(OriginTrackedValue.of(null, new TestOrigin) is null);
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
