// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/SpringBootApplication.java
// with EnableAutoConfiguration.java, AutoConfiguration.java, AutoConfigureAfter.java, AutoConfigureBefore.java,
// AutoConfigureOrder.java, ImportAutoConfiguration.java and AutoConfigurationPackage.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2); `Class<?>[]` attributes are `ClassRef[]`
// (AOT contract section 2); "Spring" becomes "Flint" in names (ADR-030).

/// `org.springframework.boot.autoconfigure`: the application and auto-configuration annotations.
///
/// Annotation module: a leaf of UDA structs (rulebook R2). Flint AOT reads them by fully qualified name (AOT
/// contract section 2.2) and resolves `@EnableAutoConfiguration` at build time. A starter's auto-configurations
/// are listed in its `META-INF/flint/flint.boot.autoconfigure.AutoConfiguration.imports`, one fully qualified class
/// per line, as Boot lists them in `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`.
/// `@ConditionalOnClass` is decided at build time; profiles, properties and bean conditions are decided at startup.
///
/// ```d
/// @FlintBootApplication
/// class RestServiceApplication
/// {
/// }
/// ```
module flint.boot.autoconfigure;

import flint.boot : FlintBootConfiguration;
import flint.boot.context.properties : ClassRef;

@safe:

/// Turns on auto-configuration: the auto-configurations of every starter in the build are applied, ordered and
/// filtered by their conditions.
struct EnableAutoConfiguration
{
    /// The property that turns auto-configuration off: `flint.boot.enableautoconfiguration=false`.
    enum ENABLED_OVERRIDE_PROPERTY = "flint.boot.enableautoconfiguration";

    /// Auto-configuration classes to leave out.
    ClassRef[] exclude;
    /// Auto-configuration class names to leave out.
    string[] excludeName;
}

/// Records the annotated class's package for auto-configured scanning (entities, repositories).
struct AutoConfigurationPackage
{
    /// Base packages.
    string[] basePackages;
    /// Classes whose packages are the base packages.
    ClassRef[] basePackageClasses;
}

/// The application's main annotation: `@FlintBootConfiguration`, `@EnableAutoConfiguration` and component
/// scanning of the annotated class's package. `@FlintApplication`, the ADR-029 name, is an alias.
@FlintBootConfiguration
@EnableAutoConfiguration
@AutoConfigurationPackage
struct FlintBootApplication
{
    /// Auto-configurations to leave out; an alias of `EnableAutoConfiguration.exclude`.
    ClassRef[] exclude;
    /// Auto-configuration class names to leave out; an alias of `EnableAutoConfiguration.excludeName`.
    string[] excludeName;
    /// Packages to scan for components; an alias of `ComponentScan.basePackages`.
    string[] scanBasePackages;
    /// Classes whose packages are scanned; an alias of `ComponentScan.basePackageClasses`.
    ClassRef[] scanBasePackageClasses;
    /// The bean name generator; an alias of `ComponentScan.nameGenerator`.
    ClassRef nameGenerator;
    /// Whether `@Bean` methods are proxied; an alias of `Configuration.proxyBeanMethods`.
    bool proxyBeanMethods = true;
}

/// Orders auto-configurations relative to each other.
struct AutoConfigureOrder
{
    /// `Ordered.LOWEST_PRECEDENCE`.
    enum DEFAULT_ORDER = 0;

    /// The order; lower values are applied first.
    int value = DEFAULT_ORDER;
}

/// Applies the annotated auto-configuration after the listed ones.
struct AutoConfigureAfter
{
    /// Auto-configurations that must be applied first.
    ClassRef[] value;
    /// Their names.
    string[] name;
}

/// Applies the annotated auto-configuration before the listed ones.
struct AutoConfigureBefore
{
    /// Auto-configurations that must be applied later.
    ClassRef[] value;
    /// Their names.
    string[] name;
}

/// Marks an auto-configuration class: a `@Configuration(proxyBeanMethods = false)` listed in a starter's
/// `AutoConfiguration.imports`, ordered with `before` and `after`.
@AutoConfigureBefore
@AutoConfigureAfter
struct AutoConfiguration
{
    /// The bean name of the configuration; an alias of `Configuration.value`.
    string value;
    /// Auto-configurations this one is applied before.
    ClassRef[] before;
    /// Their names.
    string[] beforeName;
    /// Auto-configurations this one is applied after.
    ClassRef[] after;
    /// Their names.
    string[] afterName;
}

/// Applies the listed auto-configurations, as tests and slices do.
struct ImportAutoConfiguration
{
    /// The auto-configurations; an alias of `classes`.
    ClassRef[] value;
    /// The auto-configurations.
    ClassRef[] classes;
    /// Auto-configurations to leave out.
    ClassRef[] exclude;
}
