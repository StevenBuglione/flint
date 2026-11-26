// Ported from Spring Boot v4.2.0 ConfigurationPropertiesTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module property_relaxed.relaxed_binding;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.boot.context.properties : ClassRef, ConfigurationProperties, EnableConfigurationProperties;
import flint.context.annotation : Configuration;

@safe:

/// Enable the relaxed-name binding probe only when requested.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "proof.properties", name: ["relaxed"], havingValue: "true")
@EnableConfigurationProperties([
    ClassRef("property_relaxed.relaxed_binding.WithRelaxedNamesProperties")
])
final class RelaxedBindingConfiguration
{
}

/// Two accessors whose property names use different capitalization.
@ConfigurationProperties("test")
final class WithRelaxedNamesProperties
{
    private string fooBar;
    private string barBAZ;

    /// Read the value mapped from FOO_BAR.
    string getFooBar() const
    {
        return fooBar;
    }

    /// Store the value mapped from FOO_BAR.
    void setFooBar(string value)
    {
        fooBar = value;
    }

    /// Read the value mapped from BAR-B-A-Z.
    string getBarBAZ() const
    {
        return barBAZ;
    }

    /// Store the value mapped from BAR-B-A-Z.
    void setBarBAZ(string value)
    {
        barBAZ = value;
    }
}
