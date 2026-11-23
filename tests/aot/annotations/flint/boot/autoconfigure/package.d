/// Fixture for Flint AOT tests: `org.springframework.boot.autoconfigure`.
module flint.boot.autoconfigure;

import flint.context.annotation : Configuration;
import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// `@EnableAutoConfiguration`.
struct EnableAutoConfiguration
{
    /// Auto-configurations to leave out.
    ClassRef[] exclude;
    /// Auto-configuration class names to leave out.
    string[] excludeName;
}

/// `@FlintBootApplication` (`@SpringBootApplication`).
@Configuration @EnableAutoConfiguration struct FlintBootApplication
{
    /// Auto-configurations to leave out.
    ClassRef[] exclude;
    /// Auto-configuration class names to leave out.
    string[] excludeName;
    /// Packages to scan; the application class's package when empty.
    string[] scanBasePackages;
    /// Whether `@Bean` methods are proxied.
    @AliasFor(annotation: ClassRef("flint.context.annotation.Configuration")) bool proxyBeanMethods = true;
}

/// `@AutoConfiguration`.
@Configuration(proxyBeanMethods: false) struct AutoConfiguration
{
    /// Auto-configurations to run before.
    ClassRef[] before;
    /// Auto-configurations to run after.
    ClassRef[] after;
}

/// `@AutoConfigureOrder`.
struct AutoConfigureOrder
{
    /// Order value.
    int value;
}
