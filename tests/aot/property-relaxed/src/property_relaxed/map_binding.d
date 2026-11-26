// Ported from Spring Boot v4.2.0 ConfigurationPropertiesTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use the Flint Java Map in the generated registry fixture.
module property_relaxed.map_binding;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.boot.context.properties : ClassRef, ConfigurationProperties, EnableConfigurationProperties;
import flint.context.annotation : Configuration;
import flint.java.util : Map;

@safe:

/// Enable the map binding probe only for the test that supplies map entries.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "proof.properties", name: ["map"], havingValue: "true")
@EnableConfigurationProperties([ClassRef("property_relaxed.map_binding.WithMapProperties")])
final class MapBindingConfiguration
{
}

/// A setter-bound map of simple values.
@ConfigurationProperties("test")
final class WithMapProperties
{
    private Map!(string, string) map;

    /// Read the bound entries.
    Map!(string, string) getMap()
    {
        return map;
    }

    /// Store the bound entries.
    void setMap(Map!(string, string) entries)
    {
        map = entries;
    }
}
