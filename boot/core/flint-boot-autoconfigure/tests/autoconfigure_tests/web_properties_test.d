/// Flint tests: `flint.web.*`, including Boot 4's `flint.web.error.*` (formerly `server.error.*`).
module autoconfigure_tests.web_properties_test;

import flint.boot.autoconfigure.web : ErrorProperties, WebProperties;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

unittest
{
    auto properties = new WebProperties;
    assert(properties.getLocaleResolver() == WebProperties.LocaleResolver.ACCEPT_HEADER);
    assert(properties.getResources().isAddMappings());
    assert(properties.getResources().getStaticLocations()[0] == "classpath:/META-INF/resources/");
    assert(properties.getError().getPath() == "/error");
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["spring.web.error.include-message", "always"], [
            "flint.web.error.whitelabel.enabled", "false"
        ], ["flint.web.locale-resolver", "fixed"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    foreach (descriptor; [
        descriptorOf!ErrorProperties(), descriptorOf!(ErrorProperties.Whitelabel)(),
        descriptorOf!(ErrorProperties.IncludeAttribute)(),
        descriptorOf!(WebProperties.LocaleResolver)(), descriptorOf!(WebProperties.Resources)()
    ])
        binder.getDescriptors().add(descriptor);
    auto properties = binder.bind!WebProperties("flint.web").get();
    assert(properties.getError().getIncludeMessage() == ErrorProperties.IncludeAttribute.ALWAYS);
    assert(!properties.getError().getWhitelabel().isEnabled());
    assert(properties.getLocaleResolver() == WebProperties.LocaleResolver.FIXED);
}
