// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/SystemEnvironmentPropertyMapperTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// mapper maps variable names to configuration property names only: the name-to-variable direction and the
// mapper's ancestor check are exercised through `SystemEnvironmentPropertySource` lookups, which is where Boot
// applies them.
module boot_tests.system_environment_property_mapper_test;

import flint.boot.context.properties.source : ConfigurationPropertyName, ConfigurationPropertyState,
    SystemEnvironmentPropertyMapper, SystemEnvironmentPropertySource;

@safe:

private string mapPropertySourceName(string propertySourceName)
{
    return SystemEnvironmentPropertyMapper.map(propertySourceName).toString();
}

/// Whether the configuration property `name` is found in an environment holding just the variable, for each of
/// `variables` (`containsExactly` of the upstream name-to-variable mapping).
private bool mapsTo(string name, string[] variables...)
{
    foreach (variable; variables)
    {
        auto source = new SystemEnvironmentPropertySource([variable: "value"]);
        if (source.getConfigurationProperty(ConfigurationPropertyName.of(name)) is null)
            return false;
    }
    return true;
}

/// The mapper's ancestor check, as `SystemEnvironmentPropertySource.containsDescendantOf` applies it.
private bool ancestorOf(ConfigurationPropertyName name, string variable)
{
    auto source = new SystemEnvironmentPropertySource([variable: "value"]);
    return source.containsDescendantOf(name) == ConfigurationPropertyState.PRESENT;
}

@("mapFromStringShouldReturnBestGuess") unittest
{
    assert(mapPropertySourceName("SERVER") == "server");
    assert(mapPropertySourceName("SERVER_PORT") == "server.port");
    assert(mapPropertySourceName("HOST_0") == "host[0]");
    assert(mapPropertySourceName("HOST_0_1") == "host[0][1]");
    assert(mapPropertySourceName("HOST_0_NAME") == "host[0].name");
    assert(mapPropertySourceName("HOST_F00_NAME") == "host.f00.name");
    assert(mapPropertySourceName("S-ERVER") == "s-erver");
}

@("mapFromConfigurationShouldReturnBestGuess") unittest
{
    assert(mapsTo("server", "SERVER", "server"));
    assert(mapsTo("server.port", "SERVER_PORT", "server_port"));
    assert(mapsTo("host[0]", "HOST_0", "host_0"));
    assert(mapsTo("host[0][1]", "HOST_0_1", "host_0_1"));
    assert(mapsTo("host[0].name", "HOST_0_NAME", "host_0_name"));
    assert(mapsTo("host.f00.name", "HOST_F00_NAME", "host_f00_name"));
    assert(mapsTo("foo.the-bar", "FOO_THEBAR", "FOO_THE_BAR", "foo_thebar", "foo_the_bar"));
}

@("underscoreShouldMapToEmptyString") unittest
{
    auto mapped = SystemEnvironmentPropertyMapper.map("_");
    assert(mapped.isEmpty());
}

@("underscoreWithWhitespaceShouldMapToEmptyString") unittest
{
    auto mapped = SystemEnvironmentPropertyMapper.map(" _");
    assert(mapped.isEmpty());
}

@("isAncestorOfConsidersLegacyNames") unittest
{
    auto name = ConfigurationPropertyName.of("my.spring-boot");
    assert(ancestorOf(name, "MY_SPRING_BOOT_PROPERTY"));
    assert(ancestorOf(name, "MY_SPRINGBOOT_PROPERTY"));
    assert(!ancestorOf(name, "MY_BOOT_PROPERTY"));
}

@("isAncestorOfWhenNonCanonicalSource") unittest
{
    auto name = ConfigurationPropertyName.adapt("my.springBoot", '.');
    assert(name.isAncestorOf(ConfigurationPropertyName.of("my.spring-boot.property")));
    assert(name.isAncestorOf(ConfigurationPropertyName.of("my.springboot.property")));
    assert(!name.isAncestorOf(ConfigurationPropertyName.of("my.boot.property")));
}

@("isAncestorOfWhenNonCanonicalAndDashedSource") unittest
{
    auto name = ConfigurationPropertyName.adapt("my.springBoot.input-value", '.');
    assert(name.isAncestorOf(ConfigurationPropertyName.of("my.spring-boot.input-value.property")));
    assert(name.isAncestorOf(ConfigurationPropertyName.of("my.springboot.inputvalue.property")));
    assert(!name.isAncestorOf(ConfigurationPropertyName.of("my.boot.property")));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
