// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/context/properties/ConfigurationProperties.java
// with EnableConfigurationProperties.java and ConfigurationPropertiesScan.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2); `Class<?>[]` attributes are `ClassRef[]`.

/// `org.springframework.boot.context.properties`: the `@ConfigurationProperties` annotations.
///
/// Annotation module: a leaf that declares only UDA structs (rulebook R2), so Flint AOT's generated code may import
/// it. Flint AOT reads these by their fully qualified names (AOT contract section 2.2) and emits the binding: a
/// `@ConfigurationProperties` bean is bound by `flint.boot.context.properties.bind.Binder` from the environment.
module flint.boot.context.properties;

@safe:

/// Marks a type, or a `@Bean` method, whose properties bind from configuration under a prefix:
/// `@ConfigurationProperties("flint.datasource")`.
struct ConfigurationProperties
{
    /// The prefix of the properties to bind; an alias of `prefix`.
    string value;
    /// The prefix of the properties to bind; an alias of `value`.
    string prefix;
    /// Whether invalid fields (a value that does not convert) are ignored instead of failing startup.
    bool ignoreInvalidFields = false;
    /// Whether unknown fields under the prefix are ignored.
    bool ignoreUnknownFields = true;
}

/// A fully qualified D type name, as `classOf!T` in `flint.core.annotation` produces it. Boot keeps its own
/// spelling until framework-core publishes `flint.core.annotation.ClassRef`, whose layout this matches.
struct ClassRef
{
    /// The fully qualified D name.
    string name;
}

/// Registers the listed `@ConfigurationProperties` types as beans: `@EnableConfigurationProperties([classOf!X])`.
struct EnableConfigurationProperties
{
    /// The types to register.
    ClassRef[] value;
}

/// Scans packages for `@ConfigurationProperties` types and registers them as beans.
struct ConfigurationPropertiesScan
{
    /// The packages to scan; an alias of `basePackages`.
    string[] value;
    /// The packages to scan.
    string[] basePackages;
    /// Types whose packages are scanned.
    ClassRef[] basePackageClasses;
}
