// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnMissingBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: select the user bean with a property so one registry can exercise both cases.
module property_conditions.missing_bean;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnProperty;
import flint.context.annotation : Bean, Configuration;

@safe:

/// A type supplied either by the user or by the fallback factory.
final class ExampleBean
{
}

/// User configuration that may register an ExampleBean.
@Configuration(proxyBeanMethods: false)
class ExampleBeanConfiguration
{
    /// The user-supplied bean.
    @Bean
    @ConditionalOnProperty(name: ["test.example-bean"])
    ExampleBean exampleBean()
    {
        return new ExampleBean();
    }
}

/// Supplies a default ExampleBean when the user omits it.
@Configuration(proxyBeanMethods: false)
class ImpliedOnBeanMethodConfiguration
{
    /// The condition infers the bean type from the method's return type.
    @Bean
    @ConditionalOnMissingBean
    ExampleBean exampleBean2()
    {
        return new ExampleBean();
    }
}

/// A named fallback uses the default search through the context hierarchy.
@Configuration(proxyBeanMethods: false)
@ConditionalOnMissingBean(name: ["foo"])
class HierarchyConsideredConfiguration
{
    /// Registered if no context in the hierarchy defines foo.
    @Bean
    Object bar()
    {
        return new Object();
    }
}
