// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/ConfigurationPropertyStateTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. A D enum has
// no static methods, so `ConfigurationPropertyState.search` would be a module-level `search`.
module boot_tests.configuration_property_state_test;

@safe:

version (FlintConfigurationPropertyStateSearch)
{
    // Gap: ConfigurationPropertyState.search is not ported (Flint's sources answer containsDescendantOf directly).
    import boot_tests.support : assertThrows;
    import flint.boot.context.properties.source : ConfigurationPropertyState, search;
    import flint.java.lang : IllegalArgumentException;

    @("searchWhenIterableIsNullShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { search!string(null, (string) => true); },
                "'source' must not be null");
    }

    @("searchWhenPredicateIsNullShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { search!string([], null); }, "'predicate' must not be null");
    }

    @("searchWhenContainsItemShouldReturnPresent") unittest
    {
        const result = search(["a", "b", "c"], (string e) => e == "b");
        assert(result == ConfigurationPropertyState.PRESENT);
    }

    @("searchWhenContainsNoItemShouldReturnAbsent") unittest
    {
        const result = search(["a", "x", "c"], (string e) => e == "b");
        assert(result == ConfigurationPropertyState.ABSENT);
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
