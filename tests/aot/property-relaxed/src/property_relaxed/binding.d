/// Real Boot configuration properties for the AOT binding fixture.
module property_relaxed.binding;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.boot.context.properties : ClassRef, ConfigurationProperties, EnableConfigurationProperties;
import flint.context.annotation : Configuration;

@safe:

/// Enable the binding probe only for the test that runs FlintApplication.
@Configuration(proxyBeanMethods: false)
@ConditionalOnProperty(prefix: "proof.properties", name: ["enabled"], havingValue: "true")
@EnableConfigurationProperties([
    ClassRef("property_relaxed.binding.NamedPrefixProperties"),
    ClassRef("property_relaxed.binding.ValuePrefixProperties"),
    ClassRef("property_relaxed.binding.NamedPrefixProperties")
])
final class BindingConfiguration
{
}

/// Binding through the named prefix attribute.
@ConfigurationProperties(prefix: "proof.named")
final class NamedPrefixProperties
{
    private int level;

    /// The configured level.
    int getLevel() const
    {
        return level;
    }

    /// Set the configured level.
    void setLevel(int level)
    {
        this.level = level;
    }
}

/// Binding through the shorthand value attribute.
@ConfigurationProperties("proof.value")
final class ValuePrefixProperties
{
    private int level;

    /// The configured level.
    int getLevel() const
    {
        return level;
    }

    /// Set the configured level.
    void setLevel(int level)
    {
        this.level = level;
    }
}
