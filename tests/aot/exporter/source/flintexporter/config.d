/// Fixture: a platform module that describes its own data types, compiled once with the platform, so the
/// generated module calls `flintAotDescriptors` instead of instantiating descriptors (aot-contract.md section 3).
module flintexporter.config;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.context.properties : ConfigurationProperties, EnableConfigurationProperties;
import flint.core.annotation : ClassRef;
import flint.engine.aot.descriptor : Descriptor, descriptorOf;

@safe:

/// Bound from `exporter.*`; its `string[]` property would otherwise get a container descriptor.
@ConfigurationProperties("exporter") class ExporterProperties
{
    /// Names.
    string[] names;
}

/// Enables the properties.
@AutoConfiguration @EnableConfigurationProperties([ClassRef("flintexporter.config.ExporterProperties")])
class ExporterAutoConfiguration
{
}

/// The module's descriptors, as the generator would have produced them.
Descriptor[] flintAotDescriptors()
{
    return [descriptorOf!ExporterProperties(), descriptorOf!(string[])()];
}
