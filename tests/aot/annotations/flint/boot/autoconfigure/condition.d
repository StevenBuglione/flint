/// Fixture for Flint AOT tests: `org.springframework.boot.autoconfigure.condition`.
module flint.boot.autoconfigure.condition;

import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// `@ConditionalOnProperty`.
struct ConditionalOnProperty
{
    /// Alias of `name`.
    @AliasFor("name")
    string[] value;
    /// Prefix applied to each name.
    string prefix;
    /// Property names.
    @AliasFor("value")
    string[] name;
    /// Expected value; empty means "present and not false".
    string havingValue;
    /// Whether a missing property matches.
    bool matchIfMissing;
}

/// `@ConditionalOnBean`.
struct ConditionalOnBean
{
    /// Bean types.
    ClassRef[] value;
    /// Bean type names.
    string[] type;
    /// Bean names.
    string[] name;
}

/// `@ConditionalOnMissingBean`.
struct ConditionalOnMissingBean
{
    /// Bean types.
    ClassRef[] value;
    /// Bean type names.
    string[] type;
    /// Bean names.
    string[] name;
}

/// `@ConditionalOnClass`.
struct ConditionalOnClass
{
    /// Classes, which must therefore be importable.
    ClassRef[] value;
    /// Class names.
    string[] name;
}

/// `@ConditionalOnMissingClass`.
struct ConditionalOnMissingClass
{
    /// Class names.
    string[] value;
}
