// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/SpringIterableConfigurationPropertySourceTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Boot's
// adapter over an enumerable property source with the DefaultPropertyMapper is Flint's
// `MapConfigurationPropertySource`, and with the SystemEnvironmentPropertyMapper it is
// `SystemEnvironmentPropertySource`; changes to the underlying map are `put` calls.
// Not ported: concurrentModificationExceptionInvalidatesCache (a Java map throwing
// ConcurrentModificationException during iteration; Flint's source owns its keys).
module boot_tests.spring_iterable_configuration_property_source_test;

import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertyState, MapConfigurationPropertySource, SystemEnvironmentPropertySource;

@safe:

private ConfigurationPropertyName name(string text)
{
    return ConfigurationPropertyName.of(text);
}

version (FlintPropertyMapperApi)
{
    // Gap: the adapter cannot be built over a spring-core property source with custom PropertyMappers (Flint's
    // map source takes one key-to-name mapper and has no name-to-key mapping).
    import boot_tests.support : assertThrows;
    import flint.boot.context.properties.source : PropertyMapper, SpringIterableConfigurationPropertySource;
    import flint.core.env : MapPropertySource;
    import flint.engine.aot.any : Any;
    import flint.java.lang : IllegalArgumentException;
    import flint.java.util : LinkedHashMap;

    /// `TestPropertyMapper`.
    final class TestPropertyMapper : PropertyMapper
    {
        private ConfigurationPropertyName[string] fromSource;
        private string[][string] fromConfiguration;

        /// Part of the upstream test fixture.
        void addFromPropertySource(string from, string to)
        {
            fromSource[from] = ConfigurationPropertyName.of(to);
        }

        /// Part of the upstream test fixture.
        void addFromConfigurationProperty(ConfigurationPropertyName from, string[] to...)
        {
            fromConfiguration[from.toString()] = to.dup;
        }

        /// Part of the upstream test fixture.
        string[] map(ConfigurationPropertyName configurationPropertyName)
        {
            auto found = configurationPropertyName.toString() in fromConfiguration;
            return found ? *found : null;
        }

        /// Part of the upstream test fixture.
        ConfigurationPropertyName map(string propertySourceName)
        {
            auto found = propertySourceName in fromSource;
            return found ? *found : ConfigurationPropertyName.EMPTY;
        }
    }

    private MapPropertySource mapSource(string sourceName, string[2][] entries)
    {
        auto map = new LinkedHashMap!(string, Any);
        foreach (entry; entries)
            map.put(entry[0], Any.of(entry[1]));
        return new MapPropertySource(sourceName, map);
    }

    @("createWhenPropertySourceIsNullShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() {
            new SpringIterableConfigurationPropertySource(null, false, new TestPropertyMapper);
        }, "'propertySource' must not be null");
    }

    @("iteratorShouldAdaptNames") unittest
    {
        auto propertySource = mapSource("test", [
            ["key1", "value1"], ["key2", "value2"], ["key3", "value3"], ["key4", "value4"]
        ]);
        auto mapper1 = new TestPropertyMapper;
        mapper1.addFromPropertySource("key1", "my.key1");
        mapper1.addFromPropertySource("key2", "my.key2a");
        mapper1.addFromPropertySource("key4", "my.key4");
        auto mapper2 = new TestPropertyMapper;
        mapper2.addFromPropertySource("key2", "my.key2b");
        auto adapter = new SpringIterableConfigurationPropertySource(propertySource, false, mapper1, mapper2);
        string[] names;
        foreach (n; adapter.iterator())
            names ~= n.toString();
        assert(names == ["my.key1", "my.key2a", "my.key4"]);
    }

    @("getValueShouldUseDirectMapping") unittest
    {
        auto propertySource = mapSource("test", [
            ["key1", "value1"], ["key2", "value2"], ["key3", "value3"]
        ]);
        auto mapper = new TestPropertyMapper;
        auto key = name("my.key");
        mapper.addFromConfigurationProperty(key, "key2");
        auto adapter = new SpringIterableConfigurationPropertySource(propertySource, false, mapper);
        auto configurationProperty = adapter.getConfigurationProperty(key);
        assert(configurationProperty !is null);
        assert(configurationProperty.getValue() == "value2");
    }

    @("getValueShouldUseEnumerableMapping") unittest
    {
        auto propertySource = mapSource("test", [
            ["key1", "value1"], ["key2", "value2"], ["key3", "value3"]
        ]);
        auto mapper = new TestPropertyMapper;
        mapper.addFromPropertySource("key1", "my.missing");
        mapper.addFromPropertySource("key2", "my.k-e-y");
        auto adapter = new SpringIterableConfigurationPropertySource(propertySource, false, mapper);
        auto configurationProperty = adapter.getConfigurationProperty(name("my.key"));
        assert(configurationProperty !is null);
        assert(configurationProperty.getValue() == "value2");
    }
}

version (FlintPropertySourceOriginText)
{
    // Gap: a map source's default origin reads `test - my.key`, not Boot's `"my.key" from property source "test"`.
    @("getValueOrigin") unittest
    {
        auto adapter = new MapConfigurationPropertySource("test", [["my.key", "value"]]);
        auto configurationProperty = adapter.getConfigurationProperty(name("my.key"));
        assert(configurationProperty !is null);
        assert(configurationProperty.getOrigin() == `"my.key" from property source "test"`);
    }
}

@("getValueWhenOriginCapableShouldIncludeSourceOrigin") unittest
{
    auto adapter = new MapConfigurationPropertySource("test");
    adapter.put("my.key", "value", "TestOrigin key");
    auto configurationProperty = adapter.getConfigurationProperty(name("my.key"));
    assert(configurationProperty !is null);
    assert(configurationProperty.getOrigin() == "TestOrigin key");
}

@("containsDescendantOfShouldCheckSourceNames") unittest
{
    auto adapter = new MapConfigurationPropertySource("test", [
        ["foo.bar", "value"], ["faf", "value"]
    ]);
    assert(adapter.containsDescendantOf(name("foo")) == ConfigurationPropertyState.PRESENT);
    assert(adapter.containsDescendantOf(name("faf")) == ConfigurationPropertyState.ABSENT);
    assert(adapter.containsDescendantOf(name("fof")) == ConfigurationPropertyState.ABSENT);
}

@("containsDescendantOfWhenSystemEnvironmentPropertySourceShouldSupportLegacyProperty") unittest
{
    auto adapter = new SystemEnvironmentPropertySource([
        "FOO_BAR_BAZ_BONG": "bing",
        "FOO_ALPHABRAVO_GAMMA": "delta",
        "loo_bar_baz_bong": "bing",
        "loo_alphabravo_gamma": "delta"
    ]);
    assert(adapter.containsDescendantOf(name("foo.bar-baz")) == ConfigurationPropertyState.PRESENT);
    assert(adapter.containsDescendantOf(name("foo.alpha-bravo")) == ConfigurationPropertyState.PRESENT);
    assert(adapter.containsDescendantOf(name("foo.blah")) == ConfigurationPropertyState.ABSENT);
    assert(adapter.containsDescendantOf(name("loo.bar-baz")) == ConfigurationPropertyState.PRESENT);
    assert(adapter.containsDescendantOf(name("loo.alpha-bravo")) == ConfigurationPropertyState.PRESENT);
    assert(adapter.containsDescendantOf(name("loo.blah")) == ConfigurationPropertyState.ABSENT);
}

@("getConfigurationPropertyWhenSystemEnvironmentPropertySourceShouldSupportLegacyProperty") unittest
{
    auto adapter = new SystemEnvironmentPropertySource([
        "TEST_VALUE_UPPER": "upper",
        "test_value_lower": "lower"
    ]);
    auto valueUpper = adapter.getConfigurationProperty(name("test.value-upper"));
    assert(valueUpper !is null);
    assert(valueUpper.getValue() == "upper");
    auto valueLower = adapter.getConfigurationProperty(name("test.value-lower"));
    assert(valueLower !is null);
    assert(valueLower.getValue() == "lower");
}

@("simpleMapPropertySourceKeyDataChangeInvalidatesCache") unittest
{
    auto adapter = new MapConfigurationPropertySource("test", [
        ["key1", "value1"], ["key2", "value2"]
    ]);
    assert(adapter.iterator().length == 2);
    adapter.put("key3", "value3");
    assert(adapter.iterator().length == 3);
}

@("originTrackedMapPropertySourceKeyAdditionInvalidatesCache") unittest
{
    auto adapter = new MapConfigurationPropertySource("test", [
        ["key1", "value1"], ["key2", "value2"]
    ]);
    assert(adapter.iterator().length == 2);
    adapter.put("key3", "value3");
    assert(adapter.iterator().length == 3);
}

version (FlintConfigurationPropertyCaching)
{
    // Gap: there are no immutable (read-only) origin-tracked sources whose names Flint would cache.
    import flint.boot.env : OriginTrackedMapPropertySource;

    @("readOnlyOriginTrackedMapPropertySourceKeyAdditionDoesNotInvalidateCache") unittest
    {
        auto map = ["key1": "value1", "key2": "value2"];
        auto source = new OriginTrackedMapPropertySource("test", map, true);
        auto adapter = new MapConfigurationPropertySource(source);
        assert(adapter.iterator().length == 2);
        map["key3"] = "value3";
        assert(adapter.iterator().length == 2);
    }
}

@("orderOfUnderlyingSourceIsPreserved") unittest
{
    auto propertySource = new MapConfigurationPropertySource("test", [
        ["test.map.alpha", "value1"], ["test.map.bravo", "value2"], ["test.map.charlie", "value3"],
        ["test.map.delta", "value4"]
    ]);
    string[] names;
    foreach (n; propertySource.iterator())
        names ~= n.toString();
    assert(names == ["test.map.alpha", "test.map.bravo", "test.map.charlie", "test.map.delta"]);
}

@("cacheRefreshRecalculatesDescendants") unittest
{
    auto propertySource = new MapConfigurationPropertySource("test", [["one.two.three", "test"]]);
    assert(propertySource.containsDescendantOf(name("one.two")) == ConfigurationPropertyState.PRESENT);
    propertySource.put("new", "value");
    assert(propertySource.containsDescendantOf(name("one.two")) == ConfigurationPropertyState.PRESENT);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
