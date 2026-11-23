/// Flint tests: `flint.sql.init.*` carries Boot's defaults and binds with Boot's keys.
module sql_init_properties_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.sql.autoconfigure.init : SqlInitializationProperties;
import flint.boot.sql.init : DatabaseInitializationMode;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

unittest
{
    auto properties = new SqlInitializationProperties;
    assert(properties.getPlatform() == "all" && properties.getSeparator() == ";");
    assert(!properties.isContinueOnError());
    assert(properties.getMode() == DatabaseInitializationMode.EMBEDDED);
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["spring.sql.init.mode", "always"], ["flint.sql.init.continue-on-error", "true"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    binder.getDescriptors().add(descriptorOf!DatabaseInitializationMode());
    auto properties = binder.bind!SqlInitializationProperties("flint.sql.init").get();
    assert(properties.getMode() == DatabaseInitializationMode.ALWAYS);
    assert(properties.isContinueOnError());
}
