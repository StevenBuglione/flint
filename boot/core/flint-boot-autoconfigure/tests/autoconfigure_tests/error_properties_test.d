/// Flint tests: `server.error.*` defaults and binding with Boot's names.
module autoconfigure_tests.error_properties_test;

import flint.boot.autoconfigure.web : ErrorProperties;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;

@safe:

unittest
{
    auto properties = new ErrorProperties;
    assert(properties.getPath() == "/error");
    assert(!properties.isIncludeException());
    assert(properties.getIncludeStacktrace() == ErrorProperties.IncludeAttribute.NEVER);
    assert(properties.getIncludeMessage() == ErrorProperties.IncludeAttribute.NEVER);
    assert(properties.getIncludeBindingErrors() == ErrorProperties.IncludeAttribute.NEVER);
    assert(properties.getIncludePath() == ErrorProperties.IncludeAttribute.ALWAYS);
    assert(properties.getWhitelabel().isEnabled());
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["server.error.path", "/oops"], ["server.error.include-exception", "true"]
    ]);
    auto properties = new Binder([cast(ConfigurationPropertySource) source]).bind!ErrorProperties(
            "server.error").get();
    assert(properties.getPath() == "/oops");
    assert(properties.isIncludeException());
}
