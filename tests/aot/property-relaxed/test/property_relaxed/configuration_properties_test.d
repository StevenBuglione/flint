/// Startup binding checks using Flint's generated registry and Boot Binder.
module property_relaxed.configuration_properties_test;

import flint.boot : FlintApplication, WebApplicationType;
import flint.boot.context.properties : ClassRef;
import property_relaxed.binding : NamedPrefixProperties, ValuePrefixProperties;

@safe:

@("ConfigurationProperties binds through both prefix spellings")
unittest
{
    auto application = new FlintApplication(ClassRef("property_relaxed.app.PropertyRelaxedApplication"));
    application.setWebApplicationType(WebApplicationType.NONE);
    application.setOutput((string) {});
    auto context = application.run([
        "--flint.boot.enableautoconfiguration=false", "--proof.properties.enabled=true",
        "--proof.named.level=12", "--proof.value.level=34"
    ]);
    scope (exit)
        context.close();

    auto factory = context.getBeanFactory();
    auto named = cast(NamedPrefixProperties) factory.getBean(
            "proof.named-property_relaxed.binding.NamedPrefixProperties");
    auto value = cast(ValuePrefixProperties) factory.getBean(
            "proof.value-property_relaxed.binding.ValuePrefixProperties");
    assert(named !is null && named.getLevel() == 12, "the named prefix binds level");
    assert(value !is null && value.getLevel() == 34, "the value prefix binds level");
}
