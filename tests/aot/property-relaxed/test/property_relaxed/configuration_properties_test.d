/// Startup binding checks using Flint's generated registry and Boot Binder.
module property_relaxed.configuration_properties_test;

import flint.boot : FlintApplication, WebApplicationType;
import flint.boot.context.properties : ClassRef, ConfigurationProperties;
import flint.boot.context.properties.bind : BindException;
import flint.boot.diagnostics : findCause;
import property_relaxed.binding : NamedPrefixProperties, ValuePrefixProperties;

@safe:

private auto runBinding(string[] properties...)
{
    auto application = new FlintApplication(ClassRef("property_relaxed.app.PropertyRelaxedApplication"));
    application.setWebApplicationType(WebApplicationType.NONE);
    application.setOutput((string) {});
    return application.run(["--flint.boot.enableautoconfiguration=false"] ~ properties);
}

@("ConfigurationProperties binds through both prefix spellings and ignores unknown fields by default")
unittest
{
    static assert(ConfigurationProperties.init.ignoreUnknownFields);
    auto context = runBinding("--proof.properties.enabled=true", "--proof.named.level=12",
            "--proof.value.level=34", "--proof.named.unmapped=unknown");
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

@("ConfigurationProperties rejects invalid fields by default")
unittest
{
    static assert(!ConfigurationProperties.init.ignoreInvalidFields);
    try
    {
        auto context = runBinding("--proof.properties.enabled=true", "--proof.named.level=12",
                "--proof.value.level=not-a-number");
        context.close();
    }
    catch (Exception failure)
    {
        auto bindingFailure = findCause!BindException(failure);
        if (bindingFailure is null)
            throw failure;

        auto property = bindingFailure.getProperty();
        assert(property !is null && property.getName().toString() == "proof.value.level",
                "the invalid binding should identify the property");
        return;
    }
    assert(false, "the invalid integer must fail startup");
}

@("A disabled enabling configuration registers no properties beans")
unittest
{
    auto context = runBinding("--proof.properties.enabled=false", "--proof.named.level=12", "--proof.value.level=34");
    scope (exit)
        context.close();

    assert(!context.containsLocalBean("bindingConfiguration"), "the enabling configuration must remain disabled");
    assert(!context.containsLocalBean("proof.named-property_relaxed.binding.NamedPrefixProperties"),
            "the disabled configuration must not register the named prefix");
    assert(!context.containsLocalBean("proof.value-property_relaxed.binding.ValuePrefixProperties"),
            "the disabled configuration must not register the value prefix");
}
