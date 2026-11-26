// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnWebApplicationTests.java
// with ConditionalOnNotWebApplicationTests.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use a class for the result value and name each generated configuration.
module web_conditions.app;

import flint.boot.autoconfigure : FlintBootApplication;
import flint.boot.autoconfigure.condition : ConditionalOnNotWebApplication, ConditionalOnWebApplication;
import flint.context.annotation : Bean, Configuration;

@safe:

/// The package that Flint AOT scans.
@FlintBootApplication
final class WebConditionsApplication
{
}

/// Value provided by a conditional bean.
final class BeanValue
{
    /// The registered bean's value.
    immutable string text;

    /// Create a bean with its text.
    this(string text)
    {
        this.text = text;
    }
}

/// Matches either kind of web application by default.
@Configuration(proxyBeanMethods: false)
@ConditionalOnWebApplication
class AnyWebApplicationConfiguration
{
    /// Registered in both web application types.
    @Bean
    BeanValue any()
    {
        return new BeanValue("any");
    }
}

/// Matches a servlet application.
@Configuration(proxyBeanMethods: false)
@ConditionalOnWebApplication(ConditionalOnWebApplication.Type.SERVLET)
class ServletWebApplicationConfiguration
{
    /// Registered in a servlet application.
    @Bean
    BeanValue servlet()
    {
        return new BeanValue("servlet");
    }
}

/// Matches a reactive web application.
@Configuration(proxyBeanMethods: false)
@ConditionalOnWebApplication(ConditionalOnWebApplication.Type.REACTIVE)
class ReactiveWebApplicationConfiguration
{
    /// Registered in a reactive web application.
    @Bean
    BeanValue reactive()
    {
        return new BeanValue("reactive");
    }
}

/// Matches an application with no web context type.
@Configuration(proxyBeanMethods: false)
@ConditionalOnNotWebApplication
class NotWebApplicationConfiguration
{
    /// Registered in a non-web application.
    @Bean
    BeanValue none()
    {
        return new BeanValue("none");
    }
}
