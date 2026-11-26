/// Tests Boot's generated auto-configuration startup switch against the real registry.
module property_relaxed.enable_auto_configuration_test;

import flint.boot : ApplicationEnvironment;
import flint.boot.autoconfigure : EnableAutoConfiguration;
import flint.boot.context.config : ConfigDataResult, Profiles;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.context.support : GenericApplicationContext;

@safe:

private enum overrideProperty = EnableAutoConfiguration.ENABLED_OVERRIDE_PROPERTY;
private enum springOverrideProperty = "spring.boot.enableautoconfiguration";
static assert(overrideProperty == "flint.boot.enableautoconfiguration");

private void expectAvailabilityAutoConfiguration(bool enabled, const string[2][] entries = null,
        const string[2][] defaults = null)
{
    auto context = new GenericApplicationContext();
    scope (exit)
        context.close();

    auto overrides = new MapConfigurationPropertySource("overrides", entries);
    auto fallback = new MapConfigurationPropertySource("defaults", defaults);
    // The plain context has no Boot binder. Keep the availability auto-configuration as the independent candidate.
    enum messageSource = "flint.boot.autoconfigure.context.MessageSourceAutoConfiguration";
    auto exclusions = new MapConfigurationPropertySource("fixture-exclusions",
            [["flint.autoconfigure.exclude", messageSource]]);
    auto profiles = new Profiles(null, ["default"]);
    ConfigurationPropertySource[] sources = [overrides, fallback, exclusions];
    context.setEnvironment(new ApplicationEnvironment(new ConfigDataResult(sources, profiles)));
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
    expectAvailabilityAutoConfiguration(false, [[springOverrideProperty, "false"]]);
}

@("The Flint auto-configuration key takes precedence within a property source")
unittest
{
    expectAvailabilityAutoConfiguration(false, [
        [springOverrideProperty, "true"], [overrideProperty, "false"]
    ]);
    expectAvailabilityAutoConfiguration(true, [
        [overrideProperty, "true"], [springOverrideProperty, "false"]
    ]);
}

@("The auto-configuration override respects property source precedence across aliases")
unittest
{
    expectAvailabilityAutoConfiguration(false, [[springOverrideProperty, "false"]], [
        [overrideProperty, "true"]
    ]);
    expectAvailabilityAutoConfiguration(true, [[overrideProperty, "true"]], [
        [springOverrideProperty, "false"]
    ]);
}
