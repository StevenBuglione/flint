// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use distinct bean names in the generated registry.
module property_relaxed.app;

import flint.boot.autoconfigure : FlintBootApplication;
import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.context.annotation : Bean, Configuration;
import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// The package that Flint AOT scans.
@FlintBootApplication
final class PropertyRelaxedApplication
{
}

void main()
{
}

/// Matches a relaxed property name under the Flint prefix.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "flint.", name: ["the-relaxed-property"])
class RelaxedPropertiesRequiredConfiguration
{
    /// Registered for a matching relaxed key.
    @Bean
    Object withRelaxedName()
    {
        return new Object();
    }
}

/// Matches a true value or an absent property.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "simple", name: ["my-property"], havingValue: "true", matchIfMissing: true)
class EnabledIfNotConfiguredOtherwiseConfig
{
    /// Registered when the enabled condition matches.
    @Bean
    Object enabledByDefault()
    {
        return new Object();
    }
}

/// Requires a true value under the prefixed key.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "simple", name: ["my-property"], havingValue: "true")
class DisabledIfNotConfiguredOtherwiseConfig
{
    /// Registered when the property is present and true.
    @Bean
    Object disabledByDefault()
    {
        return new Object();
    }
}

/// Both SimpleValueConfig and PrefixValueConfig use this condition upstream.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "simple", name: ["my-property"], havingValue: "bar")
class RequiredStringConfiguration
{
    /// Registered when the value of the prefixed key matches.
    @Bean
    Object withRequiredString()
    {
        return new Object();
    }
}

/// Composes the property condition for the feature's enabled key.
@ConditionalOnProperty(prefix: "my.feature", name: ["enabled"], havingValue: "true")
struct ConditionalOnMyFeature
{
}

/// Composes a property condition with a caller-selected prefix.
@ConditionalOnProperty(name: ["enabled"], havingValue: "true")
struct ConditionalOnMyFeatureWithAlias
{
    /// Overrides the property's prefix in the composed condition.
    @AliasFor(annotation: ClassRef("flint.boot.autoconfigure.condition.ConditionalOnProperty"), attribute: "prefix")
    string value;
}

/// Uses the feature's composed condition.
@Configuration(proxyBeanMethods: false)
@ConditionalOnMyFeature
class MetaAnnotation
{
    /// Registered when the composed property condition matches.
    @Bean
    Object withMeta()
    {
        return new Object();
    }
}

/// Supplies the feature prefix through the annotation's value alias.
@Configuration(proxyBeanMethods: false)
@ConditionalOnMyFeatureWithAlias("my.feature")
class MetaAnnotationWithAlias
{
    /// Registered when the aliased property condition matches.
    @Bean
    Object withAliasedMeta()
    {
        return new Object();
    }
}
