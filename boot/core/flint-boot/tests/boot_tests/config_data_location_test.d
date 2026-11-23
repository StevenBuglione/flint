// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ConfigDataLocationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// `ConfigDataLocation` is a struct; `split()` on `;` is `ConfigDataLocation.groups(value)[0]` (one group).
module boot_tests.config_data_location_test;

import flint.boot.context.config : ConfigDataLocation;

@safe:

@("isOptionalWhenNotPrefixedWithOptionalReturnsFalse") unittest
{
    const location = ConfigDataLocation.of("test");
    assert(!location.isOptional());
}

@("isOptionalWhenPrefixedWithOptionalReturnsTrue") unittest
{
    const location = ConfigDataLocation.of("optional:test");
    assert(location.isOptional());
}

@("getValueWhenNotPrefixedWithOptionalReturnsValue") unittest
{
    const location = ConfigDataLocation.of("test");
    assert(location.getValue() == "test");
}

@("getValueWhenPrefixedWithOptionalReturnsValueWithoutPrefix") unittest
{
    const location = ConfigDataLocation.of("optional:test");
    assert(location.getValue() == "test");
}

version (FlintConfigDataLocationApi)
{
    // Gap: ConfigDataLocation has no prefix helpers, origin or split on another delimiter.
    import flint.boot.origin : Origin, TextResourceOrigin;

    private Origin origin()
    {
        return new TextResourceOrigin("test", 1, 1);
    }

    @("hasPrefixWhenPrefixedReturnsTrue") unittest
    {
        assert(ConfigDataLocation.of("optional:test:path").hasPrefix("test:"));
    }

    @("hasPrefixWhenNotPrefixedReturnsFalse") unittest
    {
        assert(!ConfigDataLocation.of("optional:file:path").hasPrefix("test:"));
    }

    @("getNonPrefixedValueWhenPrefixedReturnsNonPrefixed") unittest
    {
        assert(ConfigDataLocation.of("optional:test:path").getNonPrefixedValue("test:") == "path");
    }

    @("getNonPrefixedValueWhenNotPrefixedReturnsOriginalValue") unittest
    {
        assert(ConfigDataLocation.of("optional:file:path").getNonPrefixedValue("test:") == "file:path");
    }

    @("getOriginWhenNoOriginReturnsNull") unittest
    {
        assert(ConfigDataLocation.of("test").getOrigin() is null);
    }

    @("getOriginWhenWithOriginReturnsOrigin") unittest
    {
        auto expected = origin();
        assert(ConfigDataLocation.of("test").withOrigin(expected).getOrigin() is expected);
    }

    @("withOriginSetsOrigin") unittest
    {
        auto expected = origin();
        assert(ConfigDataLocation.of("test").withOrigin(expected).getOrigin() is expected);
    }

    @("splitOnCharReturnsElements") unittest
    {
        auto split = ConfigDataLocation.of("one::two::three").split("::");
        assert(split == [
            ConfigDataLocation.of("one"), ConfigDataLocation.of("two"), ConfigDataLocation.of("three")
        ]);
    }

    @("splitWhenHasOriginReturnsElementsWithOriginSet") unittest
    {
        auto expected = origin();
        auto split = ConfigDataLocation.of("a;b").withOrigin(expected).split();
        assert(split[0].getOrigin() is expected);
        assert(split[1].getOrigin() is expected);
    }
}

version (FlintConfigDataLocationEquality)
{
    // Gap: equality is D's field-wise struct equality, so `optional:a` differs from `a` (Boot compares the value).
    @("equalsAndHashCode") unittest
    {
        const l1 = ConfigDataLocation.of("a");
        const l2 = ConfigDataLocation.of("a");
        const l3 = ConfigDataLocation.of("optional:a");
        const l4 = ConfigDataLocation.of("b");
        assert(hashOf(l1) == hashOf(l2) && hashOf(l1) == hashOf(l3));
        assert(l1 == l2 && l1 == l3 && l1 != l4);
    }
}

@("toStringReturnsOriginalString") unittest
{
    assert(ConfigDataLocation.of("optional:test").toString() == "optional:test");
}

@("ofWhenNullValueReturnsEmptyLocation") unittest
{
    assert(ConfigDataLocation.of(null).getValue().length == 0);
}

@("ofWhenEmptyValueReturnsEmptyLocation") unittest
{
    assert(ConfigDataLocation.of("").getValue().length == 0);
}

@("ofWhenEmptyOptionalValueReturnsEmptyLocation") unittest
{
    assert(ConfigDataLocation.of("optional:").getValue().length == 0);
}

@("ofReturnsLocation") unittest
{
    assert(ConfigDataLocation.of("test").toString() == "test");
}

@("splitWhenNoSemiColonReturnsSingleElement") unittest
{
    const split = ConfigDataLocation.groups(ConfigDataLocation.of("test").toString())[0];
    assert(split == [ConfigDataLocation.of("test")]);
}

@("splitWhenSemiColonReturnsElements") unittest
{
    const split = ConfigDataLocation.groups(ConfigDataLocation.of("one;two;three").toString())[0];
    assert(split == [
        ConfigDataLocation.of("one"), ConfigDataLocation.of("two"), ConfigDataLocation.of("three")
    ]);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
