// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use distinct bean names so the configurations can share a generated registry.
module property_conditions.app;

import flint.boot.autoconfigure : FlintBootApplication;
import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.context.annotation : Bean, Configuration;

@safe:

/// The package that Flint AOT scans.
@FlintBootApplication
final class PropertyConditionsApplication
{
}

/// Requires both properties to be present and each value to match the implicit rule.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(name: ["property1", "property2"])
class MultiplePropertiesRequiredConfiguration
{
    /// Registered when both required properties match.
    @Bean
    Object bothRequired()
    {
        return new Object();
    }
}

/// Uses the Flint prefix without a trailing dot.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "flint", name: ["property"])
class ShortPrefixConfiguration
{
    /// Registered when the property under the prefix exists.
    @Bean
    Object withPrefix()
    {
        return new Object();
    }
}

/// Matches when the missing property defaults to true.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "simple", name: ["my-property"], havingValue: "true", matchIfMissing: true)
class EnabledIfNotConfiguredOtherwiseConfig
{
    /// Registered for a missing property or a true value.
    @Bean
    Object enabledByDefault()
    {
        return new Object();
    }
}

/// Requires an explicit true value.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "simple", name: ["my-property"], havingValue: "true")
class DisabledIfNotConfiguredOtherwiseConfig
{
    /// Registered only when the value is true.
    @Bean
    Object disabledByDefault()
    {
        return new Object();
    }
}

/// Matches an explicit string or the missing-property default.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(name: ["simple.myProperty"], havingValue: "bar", matchIfMissing: true)
class DefaultValueConfig
{
    /// Registered for the expected value or when the property is absent.
    @Bean
    Object withDefaultValue()
    {
        return new Object();
    }
}

/// Requires both properties under a common prefix to have the expected value.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "simple", name: ["my-property", "my-another-property"], havingValue: "bar")
class MultiValuesConfig
{
    /// Registered when both property values match.
    @Bean
    Object withMultipleValues()
    {
        return new Object();
    }
}

/// Uses the positional value attribute.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(["some.property"])
class ValueAttributeConfiguration
{
    /// Registered when the property named by value is present.
    @Bean
    Object fromValue()
    {
        return new Object();
    }
}
