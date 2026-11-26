// Ported from Spring Boot v4.2.0 ConfigurationPropertiesTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: enable binding through the generated registry.
module property_relaxed.environment_binding;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.boot.context.properties : ClassRef, ConfigurationProperties, EnableConfigurationProperties;
import flint.context.annotation : Configuration;

@safe:

/// Enable the fixture for tests that supply a controlled environment.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "proof.properties", name: ["environment"], havingValue: "true")
@EnableConfigurationProperties([
    ClassRef("property_relaxed.environment_binding.SimplePrefixedProperties")
])
final class EnvironmentBindingConfiguration
{
}

/// Configuration properties populated from the system environment source.
@ConfigurationProperties(prefix: "com.example", ignoreUnknownFields: false)
final class SimplePrefixedProperties
{
    private string bar;

    /// Read the bound property.
    string getBar() const
    {
        return bar;
    }

    /// Store the bound property.
    void setBar(string value)
    {
        bar = value;
    }
}
