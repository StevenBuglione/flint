// Ported from spring-boot v4.2.0: core/spring-boot-test/src/test/java/org/springframework/boot/test/util/TestPropertyValuesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use D unittests and the mapped collection and nullable types.
module boot_test_tests.test_property_values_tests;

import flint.boot.test.util : TestPropertyValues;
import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashMap, MapEntry;
import std.typecons : Nullable;

@safe:

private alias Pair = TestPropertyValues.Pair;

@("pairOfCreatesPair")
unittest
{
    auto properties = new LinkedHashMap!(string, Any);
    Pair.of("spring", Nullable!string("boot")).addTo(properties);
    assert(properties.size() == 1);
    assert(properties.get("spring").get!string == "boot");
}

@("pairOfWhenNameAndValueAreEmptyReturnsPair")
unittest
{
    auto pair = Pair.of("", Nullable!string(""));
    assert(pair !is null);
    auto properties = new LinkedHashMap!(string, Any);
    pair.addTo(properties);
    assert(!properties.get("").isNull() && properties.get("").get!string.length == 0);
}

@("pairFromMapEntryCreatesPair")
unittest
{
    auto properties = new LinkedHashMap!(string, Any);
    auto entry = new MapEntry!(string, Nullable!string)("spring", Nullable!string("boot"));
    Pair.fromMapEntry(entry).addTo(properties);
    assert(properties.size() == 1);
    assert(properties.get("spring").get!string == "boot");
}

@("pairFromMapEntryWithEmptyKeyCreatesPair")
unittest
{
    auto properties = new LinkedHashMap!(string, Any);
    auto entry = new MapEntry!(string, Nullable!string)("", Nullable!string("empty-key"));
    Pair.fromMapEntry(entry).addTo(properties);
    assert(properties.size() == 1);
    assert(properties.get("").get!string == "empty-key");
}

@("Property pair parsing honors the first separator and Java trim")
unittest
{
    auto properties = new LinkedHashMap!(string, Any);
    Pair.parse("\t clé : café=thé \r").addTo(properties);
    Pair.parse("hasEquals=yes:second").addTo(properties);
    Pair.parse(" \tbare \r").addTo(properties);
    Pair.parse("=no-key").addTo(properties);
    Pair.of("null", Nullable!string.init).addTo(properties);
    assert(properties.get("clé").get!string == "café=thé");
    assert(properties.get("hasEquals").get!string == "yes:second");
    assert(!properties.get("bare").isNull() && properties.get("bare").get!string.length == 0);
    assert(properties.containsKey("=no-key"));
    assert(properties.containsKey("null") && properties.get("null").isNull());
}
