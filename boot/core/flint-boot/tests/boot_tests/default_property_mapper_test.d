// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/DefaultPropertyMapperTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// mapper maps keys to names only, so mapFromConfigurationShouldReturnBestGuess checks the name-to-key direction by
// looking each name up in a `MapConfigurationPropertySource` holding the key upstream expects.
module boot_tests.default_property_mapper_test;

import flint.boot.context.properties.source : ConfigurationPropertyName, DefaultPropertyMapper,
    MapConfigurationPropertySource;

@safe:

private string mapPropertySourceName(string propertySourceName)
{
    return DefaultPropertyMapper.map(propertySourceName).toString();
}

/// Whether the configuration property `name` is found under each of `keys` (`containsExactly` of the upstream map).
private bool mapsTo(string name, string[] keys...)
{
    foreach (key; keys)
    {
        auto source = new MapConfigurationPropertySource("test", [[key, "value"]]);
        if (source.getConfigurationProperty(ConfigurationPropertyName.of(name)) is null)
            return false;
    }
    return true;
}

@("mapFromStringShouldReturnBestGuess") unittest
{
    assert(mapPropertySourceName("server") == "server");
    assert(mapPropertySourceName("server.port") == "server.port");
    assert(mapPropertySourceName("host[0]") == "host[0]");
    assert(mapPropertySourceName("host[0][1]") == "host[0][1]");
    assert(mapPropertySourceName("host[0].name") == "host[0].name");
    assert(mapPropertySourceName("host.f00.name") == "host.f00.name");
    assert(mapPropertySourceName("my.host-name") == "my.host-name");
    assert(mapPropertySourceName("my.hostName") == "my.hostname");
    assert(mapPropertySourceName("my.HOST_NAME") == "my.hostname");
    assert(mapPropertySourceName("s[!@#$%^&*()=+]e-rVeR") == "s[!@#$%^&*()=+].e-rver");
    assert(mapPropertySourceName("host[FOO].name") == "host[FOO].name");
}

@("mapFromConfigurationShouldReturnBestGuess") unittest
{
    assert(mapsTo("server", "server"));
    assert(mapsTo("server.port", "server.port"));
    assert(mapsTo("host[0]", "host[0]"));
    assert(mapsTo("host[0][1]", "host[0][1]"));
    assert(mapsTo("host[0].name", "host[0].name"));
    assert(mapsTo("host.f00.name", "host.f00.name"));
    assert(mapsTo("my.host-name", "my.host-name"));
    assert(mapsTo("host[FOO].name", "host[FOO].name"));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
