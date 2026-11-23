// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/MapConfigurationPropertySourceTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// source is keyed by strings, so the `ConfigurationPropertyName` key of createWhenMapHasEntriesShouldAdaptMap is
// given as its canonical text, and `stream()` is `iterator()`.
// Not ported: createWhenMapIsNullShouldThrowException and putAllWhenMapIsNullShouldThrowException (a null D
// associative array is the empty one).
module boot_tests.map_configuration_property_source_test;

import flint.boot.context.properties.source : ConfigurationPropertyName, MapConfigurationPropertySource;

@safe:

private string getValue(MapConfigurationPropertySource source, string name)
{
    auto property = source.getConfigurationProperty(ConfigurationPropertyName.of(name));
    return property is null ? null : property.getValue();
}

private bool containsExactly(ConfigurationPropertyName[] actual, string[] expected)
{
    if (actual.length != expected.length)
        return false;
    foreach (index, name; expected)
    {
        if (!actual[index].equals(ConfigurationPropertyName.of(name)))
            return false;
    }
    return true;
}

@("createWhenMapHasEntriesShouldAdaptMap") unittest
{
    auto source = new MapConfigurationPropertySource("map", [
        ["foo.BAR", "spring"], [ConfigurationPropertyName.of("foo.baz").toString(), "boot"]
    ]);
    assert(getValue(source, "foo.bar") == "spring");
    assert(getValue(source, "foo.baz") == "boot");
}

@("putAllShouldPutEntries") unittest
{
    auto source = new MapConfigurationPropertySource();
    source.putAll(["foo.BAR": "spring", "foo.baz": "boot"]);
    assert(getValue(source, "foo.bar") == "spring");
    assert(getValue(source, "foo.baz") == "boot");
}

@("putShouldPutEntry") unittest
{
    auto source = new MapConfigurationPropertySource();
    source.put("foo.bar", "baz");
    assert(getValue(source, "foo.bar") == "baz");
}

@("getConfigurationPropertyShouldGetFromMemory") unittest
{
    auto source = new MapConfigurationPropertySource();
    source.put("foo.bar", "baz");
    assert(getValue(source, "foo.bar") == "baz");
    source.put("foo.bar", "big");
    assert(getValue(source, "foo.bar") == "big");
}

@("iteratorShouldGetFromMemory") unittest
{
    auto source = new MapConfigurationPropertySource();
    source.put("foo.BAR", "spring");
    source.put("foo.baz", "boot");
    assert(containsExactly(source.iterator(), ["foo.bar", "foo.baz"]));
}

@("streamShouldGetFromMemory") unittest
{
    auto source = new MapConfigurationPropertySource();
    source.put("foo.BAR", "spring");
    source.put("foo.baz", "boot");
    assert(containsExactly(source.iterator(), ["foo.bar", "foo.baz"]));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
