// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnBooleanPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: assign distinct bean names to the condition fixtures.
module property_conditions.boolean_properties;

import flint.boot.autoconfigure.condition : ConditionalOnBooleanProperty;
import flint.context.annotation : Bean, Configuration;

@safe:

/// Boolean property with its default value and missing-property behavior.
@Configuration(proxyBeanMethods: false)
@ConditionalOnBooleanProperty(["test"])
class BooleanDefaultsConfiguration
{
    /// The bean registered when the property condition matches.
    @Bean
    Object booleanDefaults()
    {
        return new Object();
    }
}

/// Explicit true value required.
@Configuration(proxyBeanMethods: false)
@ConditionalOnBooleanProperty(name: ["test"], havingValue: true, matchIfMissing: false)
class BooleanTrueRequiredConfiguration
{
    /// The bean registered when the property condition matches.
    @Bean
    Object booleanTrueRequired()
    {
        return new Object();
    }
}

/// True value or a missing property.
@Configuration(proxyBeanMethods: false)
@ConditionalOnBooleanProperty(name: ["test"], havingValue: true, matchIfMissing: true)
class BooleanTrueOptionalConfiguration
{
    /// The bean registered when the property condition matches.
    @Bean
    Object booleanTrueOptional()
    {
        return new Object();
    }
}

/// Explicit false value required.
@Configuration(proxyBeanMethods: false)
@ConditionalOnBooleanProperty(name: ["test"], havingValue: false, matchIfMissing: false)
class BooleanFalseRequiredConfiguration
{
    /// The bean registered when the property condition matches.
    @Bean
    Object booleanFalseRequired()
    {
        return new Object();
    }
}

/// False value or a missing property.
@Configuration(proxyBeanMethods: false)
@ConditionalOnBooleanProperty(name: ["test"], havingValue: false, matchIfMissing: true)
class BooleanFalseOptionalConfiguration
{
    /// The bean registered when the property condition matches.
    @Bean
    Object booleanFalseOptional()
    {
        return new Object();
    }
}

/// True value under the foo prefix.
@Configuration(proxyBeanMethods: false)
@ConditionalOnBooleanProperty(prefix: "foo", name: ["test"])
class BooleanPrefixedConfiguration
{
    /// The bean registered when the property condition matches.
    @Bean
    Object booleanPrefixed()
    {
        return new Object();
    }
}
