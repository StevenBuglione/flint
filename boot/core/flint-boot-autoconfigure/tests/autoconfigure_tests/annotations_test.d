/// Flint tests: the annotations carry Boot's defaults and the meta-annotations Flint AOT merges.
module autoconfigure_tests.annotations_test;

import flint.boot.autoconfigure : AutoConfiguration, AutoConfigureAfter, AutoConfigureBefore,
    EnableAutoConfiguration, FlintBootApplication;
import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnProperty,
    ConditionalOnWebApplication, SearchStrategy;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

@FlintBootApplication
private final class App
{
}

unittest
{
    // Merged as the generator merges: @FlintBootApplication brings @EnableAutoConfiguration and the configuration.
    auto descriptor = descriptorOf!App();
    assert(descriptor.annotation("flint.boot.autoconfigure.FlintBootApplication") !is null);
    assert(descriptor.annotation("flint.boot.autoconfigure.EnableAutoConfiguration") !is null);
    assert(descriptor.annotation("flint.boot.FlintBootConfiguration") !is null);
}

unittest
{
    const property = ConditionalOnProperty.init;
    assert(!property.matchIfMissing && property.havingValue.length == 0);
    assert(ConditionalOnMissingBean.init.search == SearchStrategy.ALL);
    assert(ConditionalOnWebApplication.init.type == ConditionalOnWebApplication.Type.ANY);
    assert(FlintBootApplication.init.proxyBeanMethods);
    assert(EnableAutoConfiguration.ENABLED_OVERRIDE_PROPERTY == "flint.boot.enableautoconfiguration");
}
