/// Fixture for Flint AOT tests: `org.springframework.context.annotation`.
module flint.context.annotation;

import flint.core.annotation : AliasFor, ClassRef;
import flint.stereotype : Component;

@safe:

/// `@Import`: the classes are configuration beans, registered after their importer's class and before its
/// `@Bean` methods.
struct Import
{
    /// The classes.
    ClassRef[] value;
}

/// `@Configuration`.
@Component struct Configuration
{
    /// Bean name.
    @AliasFor(annotation : ClassRef("flint.stereotype.Component")) string value;
    /// Whether `@Bean` methods return the container's instances when called directly.
    bool proxyBeanMethods = true;
}

/// `@Bean`.
struct Bean
{
    /// Alias of `name`.
    @AliasFor("name") string[] value;
    /// Bean names; the first is the name, the others aliases.
    @AliasFor("value") string[] name;
    /// Initialization method.
    string initMethod;
    /// Destroy method; "(inferred)" looks for close or shutdown.
    string destroyMethod = "(inferred)";

    /// Java's single-value form: `@Bean("x")` (aot-contract.md section 2, R2.1).
    static Bean opCall(string value, string[] name = null, string initMethod = null, string destroyMethod = "(inferred)")
    {
        Bean result;
        result.value = [value];
        result.name = name;
        result.initMethod = initMethod;
        result.destroyMethod = destroyMethod;
        return result;
    }

    /// The array form, and the named-attribute form.
    static Bean opCall(string[] value = null, string[] name = null, string initMethod = null,
            string destroyMethod = "(inferred)")
    {
        Bean result;
        result.value = value;
        result.name = name;
        result.initMethod = initMethod;
        result.destroyMethod = destroyMethod;
        return result;
    }
}

/// `@Primary`.
struct Primary
{
}

/// `@Lazy`.
struct Lazy
{
    /// Whether initialization is lazy.
    bool value = true;
}

/// `@DependsOn`.
struct DependsOn
{
    /// Beans that must be created first.
    string[] value;
}

/// `@Scope`.
struct Scope
{
    /// Scope name.
    string value;
}

/// `@Profile`.
struct Profile
{
    /// Profile expressions; any may match.
    string[] value;

    /// Java's single-value form: `@Profile("x")` (aot-contract.md section 2, R2.1).
    static Profile opCall(string value)
    {
        Profile result;
        result.value = [value];

        return result;
    }

    /// The array form, and the named-attribute form.
    static Profile opCall(string[] value = null)
    {
        Profile result;
        result.value = value;

        return result;
    }
}
