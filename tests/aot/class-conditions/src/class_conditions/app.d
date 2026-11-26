// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnClassTests.java
// with ConditionalOnMissingClassTests.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the fixture gives each case a distinct bean name and uses a class for the result value.
module class_conditions.app;

import flint.boot.autoconfigure : FlintBootApplication;
import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingClass;
import flint.boot.context.properties : ClassRef;
import flint.context.annotation : Bean, Configuration;

@safe:

/// The package that Flint AOT scans.
@FlintBootApplication
final class ClassConditionsApplication
{
}

/// The value of a bean created by a configuration.
final class BeanValue
{
    /// Value returned by the bean method.
    string text;

    /// Create the bean with its text.
    this(string text)
    {
        this.text = text;
    }
}

/// Provides the bean that is independent of the class conditions.
@Configuration(proxyBeanMethods: false)
class FooConfiguration
{
    /// The bean used to verify unconditional registration.
    @Bean
    BeanValue foo()
    {
        return new BeanValue("foo");
    }
}

/// Matches the class reference to the application class.
@Configuration(proxyBeanMethods: false)
@ConditionalOnClass([ClassRef("class_conditions.app.ClassConditionsApplication")])
class RequirePresentClass
{
    /// Registered because the required class exists.
    @Bean
    BeanValue requirePresentBar()
    {
        return new BeanValue("bar");
    }
}

/// Requires a class by its name.
@Configuration(proxyBeanMethods: false)
@ConditionalOnClass(name: ["class_conditions.app.Absent"])
class RequireAbsentClass
{
    /// Excluded because the required class is missing.
    @Bean
    BeanValue requireAbsentBar()
    {
        return new BeanValue("bar");
    }
}

/// Requires the application class to be absent.
@Configuration(proxyBeanMethods: false)
@ConditionalOnMissingClass(["class_conditions.app.ClassConditionsApplication"])
class ExcludePresentClass
{
    /// Excluded because the class exists.
    @Bean
    BeanValue excludePresentBar()
    {
        return new BeanValue("bar");
    }
}

/// Matches a missing class by name.
@Configuration(proxyBeanMethods: false)
@ConditionalOnMissingClass(["class_conditions.app.Absent"])
class ExcludeAbsentClass
{
    /// Registered because the class is missing.
    @Bean
    BeanValue excludeAbsentBar()
    {
        return new BeanValue("bar");
    }
}
