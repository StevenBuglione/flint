/// Tests Boot's generated auto-configuration startup switch against the real registry.
module property_relaxed.enable_auto_configuration_test;

import flint.boot : ApplicationEnvironment;
import flint.boot.autoconfigure : EnableAutoConfiguration;
import flint.boot.context.config : ConfigDataResult, Profiles;
import flint.boot.context.properties.source : MapConfigurationPropertySource;
import flint.context.support : GenericApplicationContext;

@safe:

private enum overrideProperty = EnableAutoConfiguration.ENABLED_OVERRIDE_PROPERTY;
static assert(overrideProperty == "flint.boot.enableautoconfiguration");

private void expectAvailabilityAutoConfiguration(bool enabled, const string[2][] entries = null)
{
    auto context = new GenericApplicationContext();
    scope (exit)
        context.close();

    auto overrides = new MapConfigurationPropertySource("overrides", entries);
    // The plain context has no Boot binder. Keep the availability auto-configuration as the independent candidate.
    enum messageSource = "flint.boot.autoconfigure.context.MessageSourceAutoConfiguration";
    auto exclusions = new MapConfigurationPropertySource("fixture-exclusions",
            [["flint.autoconfigure.exclude", messageSource]]);
    auto profiles = new Profiles(null, ["default"]);
    context.setEnvironment(new ApplicationEnvironment(new ConfigDataResult([overrides, exclusions], profiles)));
    context.deferAotRegistry();
    context.refresh();

    enum availability = "flint.boot.autoconfigure.availability.ApplicationAvailabilityAutoConfiguration";
    assert(context.containsLocalBean(availability) == enabled, "availability auto-configuration");
    assert(context.containsLocalBean("applicationAvailability") == enabled, "applicationAvailability");
    assert(!context.containsLocalBean(messageSource));
}

@("Boot auto-configuration starts by default and follows its Flint override")
unittest
{
    expectAvailabilityAutoConfiguration(true);
    expectAvailabilityAutoConfiguration(true, [[overrideProperty, "true"]]);
    expectAvailabilityAutoConfiguration(false, [[overrideProperty, "false"]]);
}

@("Boot auto-configuration honors the Spring override property name")
unittest
{
    expectAvailabilityAutoConfiguration(false, [["spring.boot.enableautoconfiguration", "false"]]);
}
