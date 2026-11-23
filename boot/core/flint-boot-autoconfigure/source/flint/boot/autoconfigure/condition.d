// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/condition/ConditionalOnClass.java
// with ConditionalOnMissingClass.java, ConditionalOnBean.java, ConditionalOnMissingBean.java,
// ConditionalOnSingleCandidate.java, ConditionalOnProperty.java, ConditionalOnBooleanProperty.java,
// ConditionalOnWebApplication.java, ConditionalOnNotWebApplication.java, ConditionalOnResource.java,
// ConditionalOnExpression.java and SearchStrategy.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2); `Class<?>` attributes are `ClassRef`s.
// Excluded: ConditionalOnJava, ConditionalOnJndi, ConditionalOnWarDeployment, ConditionalOnNotWarDeployment and
// ConditionalOnCheckpointRestore (jvm-platform, packaging).

/// `org.springframework.boot.autoconfigure.condition`: the conditions auto-configurations use.
///
/// Flint AOT emits each condition as AOT contract section 5.5 lays out. `@ConditionalOnClass` and
/// `@ConditionalOnMissingClass` are decided at build time, from the build's dependency closure. The other
/// conditions are decided at startup, so `FLINT_PROFILES_ACTIVE` and properties set at deploy time take effect.
module flint.boot.autoconfigure.condition;

import flint.boot.context.properties : ClassRef;

@safe:

/// Matches when every listed class is in the build.
struct ConditionalOnClass
{
    /// The classes that must be present.
    ClassRef[] value;
    /// Their names, for classes that may be absent from the build.
    string[] name;
}

/// Matches when none of the listed classes is in the build.
struct ConditionalOnMissingClass
{
    /// The names of the classes that must be absent.
    string[] value;
}

/// Where bean conditions look for beans.
enum SearchStrategy
{
    /// Only the current context.
    CURRENT,
    /// The ancestor contexts.
    ANCESTORS,
    /// The whole hierarchy.
    ALL
}

/// Matches when beans of the listed types or names are already defined.
struct ConditionalOnBean
{
    /// Bean types.
    ClassRef[] value;
    /// Bean type names.
    string[] type;
    /// Annotations the beans carry.
    ClassRef[] annotation;
    /// Bean names.
    string[] name;
    /// Where to look.
    SearchStrategy search = SearchStrategy.ALL;
    /// Container types whose generic parameter is the bean type.
    ClassRef[] parameterizedContainer;
}

/// Matches when no bean of the listed types or names is defined: auto-configuration backs off for user beans.
struct ConditionalOnMissingBean
{
    /// Bean types; with none, the `@Bean` method's return type.
    ClassRef[] value;
    /// Bean type names.
    string[] type;
    /// Types to ignore.
    ClassRef[] ignored;
    /// Type names to ignore.
    string[] ignoredType;
    /// Annotations the beans carry.
    ClassRef[] annotation;
    /// Bean names.
    string[] name;
    /// Where to look.
    SearchStrategy search = SearchStrategy.ALL;
    /// Container types whose generic parameter is the bean type.
    ClassRef[] parameterizedContainer;
}

/// Matches when exactly one candidate of the type is defined, or one primary among several.
struct ConditionalOnSingleCandidate
{
    /// The bean type.
    ClassRef value;
    /// The bean type's name.
    string type;
    /// Where to look.
    SearchStrategy search = SearchStrategy.ALL;
}

/// Matches on property values: each named property must exist and not be `false`, or equal `havingValue`
/// (ignoring case). `flint.*` names also match their `spring.*` spelling.
struct ConditionalOnProperty
{
    /// The property names; an alias of `name`.
    string[] value;
    /// A prefix applied to each name.
    string prefix;
    /// The property names.
    string[] name;
    /// The expected value; empty means "present and not false".
    string havingValue;
    /// Whether a missing property matches.
    bool matchIfMissing = false;
}

/// Matches when a boolean property has the given value.
struct ConditionalOnBooleanProperty
{
    /// The property names; an alias of `name`.
    string[] value;
    /// A prefix applied to each name.
    string prefix;
    /// The property names.
    string[] name;
    /// The expected value.
    bool havingValue = true;
    /// Whether a missing property matches.
    bool matchIfMissing = false;
}

/// Matches in a web application.
struct ConditionalOnWebApplication
{
    /// The kinds of web application.
    enum Type
    {
        /// Any web application.
        ANY,
        /// A servlet-based one.
        SERVLET,
        /// A reactive one.
        REACTIVE
    }

    /// The required kind.
    Type type = Type.ANY;
}

/// Matches outside a web application.
struct ConditionalOnNotWebApplication
{
}

/// Matches when the listed resources exist.
struct ConditionalOnResource
{
    /// The resources (`classpath:schema.sql`).
    string[] resources;
}

/// Matches on a SpEL expression. Deferred to Phase 2, with SpEL compiled to D (ADR-030 section 3).
struct ConditionalOnExpression
{
    /// The expression.
    string value = "true";
}
