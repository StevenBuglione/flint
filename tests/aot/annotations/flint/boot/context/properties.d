/// Fixture for Flint AOT tests: `org.springframework.boot.context.properties`.
module flint.boot.context.properties;

import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// `@ConfigurationProperties`.
struct ConfigurationProperties
{
    /// Alias of `prefix`.
    @AliasFor("prefix")
    string value;
    /// Property prefix.
    @AliasFor("value")
    string prefix;
}

/// `@EnableConfigurationProperties`.
struct EnableConfigurationProperties
{
    /// Classes to register.
    ClassRef[] value;
}
