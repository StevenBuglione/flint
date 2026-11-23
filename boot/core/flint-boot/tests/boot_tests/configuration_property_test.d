// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/ConfigurationPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// property is built by its constructor (there is no `ConfigurationProperty.of`) and its origin is the origin's text.
module boot_tests.configuration_property_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.java.lang : IllegalArgumentException;

@safe:

private ConfigurationPropertyName name()
{
    return ConfigurationPropertyName.of("foo");
}

private ConfigurationPropertySource source()
{
    return new MapConfigurationPropertySource("test");
}

version (FlintBootNullArgumentChecks)
{
    // Gap: the constructor does not reject a null name or value.
    @("createWhenNameIsNullShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { new ConfigurationProperty(null, null, "bar"); },
                "'name' must not be null");
    }

    @("createWhenValueIsNullShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { new ConfigurationProperty(null, name(), null); },
                "'value' must not be null");
    }
}

@("getNameShouldReturnName") unittest
{
    auto expected = name();
    auto property = new ConfigurationProperty(source(), expected, "foo", null);
    assert(property.getName() is expected);
}

@("getValueShouldReturnValue") unittest
{
    auto property = new ConfigurationProperty(source(), name(), "foo", null);
    assert(property.getValue() == "foo");
}

@("getPropertyOriginShouldReturnValuePropertyOrigin") unittest
{
    const origin = "class path resource [application.properties] - 1:5";
    auto property = new ConfigurationProperty(source(), name(), "foo", origin);
    assert(property.getOrigin() == origin);
}

@("getPropertySourceShouldReturnPropertySource") unittest
{
    auto expected = source();
    auto property = new ConfigurationProperty(expected, name(), "foo", "origin");
    assert(property.getSource() is expected);
}

version (FlintConfigurationPropertyEquality)
{
    // Gap: ConfigurationProperty has no equals/hashCode (D identity equality).
    @("equalsAndHashCode") unittest
    {
        auto property1 = new ConfigurationProperty(null, ConfigurationPropertyName.of("foo"), "bar", null);
        auto property2 = new ConfigurationProperty(null, ConfigurationPropertyName.of("foo"), "bar", null);
        auto property3 = new ConfigurationProperty(null, ConfigurationPropertyName.of("foo"), "baz", null);
        auto property4 = new ConfigurationProperty(null, ConfigurationPropertyName.of("baz"), "bar", null);
        assert(property1.toHash() == property2.toHash());
        assert(property1.opEquals(property2));
        assert(!property1.opEquals(property3));
        assert(!property1.opEquals(property4));
    }
}

@("toStringShouldReturnValue") unittest
{
    import std.algorithm.searching : canFind;

    auto property = new ConfigurationProperty(source(), name(), "foo", null);
    assert(property.toString().canFind("name"));
    assert(property.toString().canFind("value"));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
