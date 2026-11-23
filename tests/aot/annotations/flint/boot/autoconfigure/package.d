/// Fixture for Flint AOT tests: `org.springframework.boot.autoconfigure`.
module flint.boot.autoconfigure;

import flint.context.annotation : Configuration;
import flint.core.annotation : AliasFor, ClassRef;

@safe:

/// `@FlintBootApplication` (`@SpringBootApplication`).
@Configuration struct FlintBootApplication
{
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
