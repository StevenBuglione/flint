/// Flint tests: `flint.jackson.*` carries Boot's defaults and binds with Boot's keys.
module jackson_properties_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jackson.autoconfigure : JacksonProperties;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

unittest
{
    auto properties = new JacksonProperties;
    assert(properties.isFindAndAddModules() && !properties.isUseJackson2Defaults());
    assert(properties.getConstructorDetector() == JacksonProperties.ConstructorDetectorStrategy.DEFAULT);
    assert(properties.getSerialization().isEmpty() && properties.getDefaultLeniency().isEmpty());
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["spring.jackson.date-format", "yyyy-MM-dd"],
        ["flint.jackson.constructor-detector", "use-properties-based"],
        ["flint.jackson.time-zone", "UTC"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    binder.getDescriptors().add(descriptorOf!(JacksonProperties.ConstructorDetectorStrategy)());
    auto properties = binder.bind!JacksonProperties("flint.jackson").get();
    assert(properties.getDateFormat() == "yyyy-MM-dd");
    assert(properties.getTimeZone() == "UTC");
    assert(properties.getConstructorDetector() == JacksonProperties.ConstructorDetectorStrategy.USE_PROPERTIES_BASED);
}
