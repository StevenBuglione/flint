// Ported from spring-boot v4.2.0: module/spring-boot-validation/src/test/java/org/springframework/boot/validation/autoconfigure/ValidationAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it, instead of through an ApplicationContextRunner; the method-validation, primary-validator and
// user-validator cases join with MethodValidationPostProcessor and the context runner.
module validation_autoconfiguration_test;

import flint.boot.validation.autoconfigure : ValidationAutoConfiguration, ValidationConfigurationCustomizer;
import flint.jakarta.validation : Configuration;
import flint.jakarta.validation.constraints : NotBlank;

@safe:

// Hibernate Validator registers itself as the provider when it is linked.
private alias provider = imported!"flint.hibernate.validator".HibernateValidator;

private final class RecordingCustomizer : ValidationConfigurationCustomizer
{
    int calls;

    void customize(Configuration configuration)
    {
        assert(configuration !is null);
        calls++;
    }
}

@("validationAutoConfigurationShouldConfigureDefaultValidator") unittest
{
    auto validator = new ValidationAutoConfiguration().defaultValidator(null);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    assert(validator.getValidator() !is null);
    assert(validator.getMessageInterpolator() !is null);
}

@("validationConfigurationCustomizersAreApplied") unittest
{
    auto first = new RecordingCustomizer;
    auto second = new RecordingCustomizer;
    auto validator = new ValidationAutoConfiguration().defaultValidator([first, second]);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    assert(first.calls == 1 && second.calls == 1);
}

private struct Address
{
    @NotBlank
    string city;
}

@("defaultValidatorUsesTheContextDescriptors") unittest
{
    import flint.context.support : GenericApplicationContext;
    import flint.engine.aot.descriptor : descriptorOf;
    import flint.engine.aot.any : Any;

    auto context = new GenericApplicationContext;
    context.getDescriptorTable().add(descriptorOf!Address());
    auto validator = new ValidationAutoConfiguration().defaultValidator(null, context);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    auto violations = validator.getValidator().validate(Any.of(Address("")));
    assert(violations.length == 1, "the blank city violates @NotBlank");
    assert(violations[0].getPropertyPath().toString() == "city");
}

@("methodValidationPostProcessorValidatesWithTheContextValidator") unittest
{
    import flint.context.support : GenericApplicationContext;

    auto context = new GenericApplicationContext;
    auto configuration = new ValidationAutoConfiguration();
    auto validator = configuration.defaultValidator(null, context);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    context.getBeanFactory().registerSingleton("defaultValidator", validator);
    context.refresh();
    scope (exit)
        context.close();
    auto processor = configuration.methodValidationPostProcessor(context);
    processor.afterPropertiesSet();
    assert(processor.getOrder() == int.max);
}

@("methodValidationPostProcessorReadsAdaptConstraintViolations") unittest
{
    import flint.context.support : GenericApplicationContext;
    import flint.core.env : MapPropertySource;
    import flint.engine.aot.any : Any;
    import flint.java.lang : UnsupportedOperationException;
    import flint.java.util : HashMap, Map;
    import std.exception : assertThrown;

    auto context = new GenericApplicationContext;
    Map!(string, Any) properties = new HashMap!(string, Any)();
    properties.put("flint.validation.method.adapt-constraint-violations", Any.of("true"));
    context.getConfigurableEnvironment().getPropertySources().addFirst(new MapPropertySource("test", properties));
    // Spring's MethodValidationException is not ported, so adapting is refused rather than ignored.
    auto configuration = new ValidationAutoConfiguration();
    assertThrown!UnsupportedOperationException(configuration.methodValidationPostProcessor(context));
}

/// A `@Validated` `@ConfigurationProperties` type with a Bean Validation constraint (Boot's
/// ConfigurationPropertiesTests' `ValidatedJsr303Properties`).
@(imported!"flint.validation.annotation".Validated) final class ValidatedJsr303Properties
{
    @(imported!"flint.jakarta.validation.constraints".Min(5)) private int value;

    /// The value.
    int getValue() const
    {
        return value;
    }

    /// Set the value.
    void setValue(int value)
    {
        this.value = value;
    }
}

// Flint test (ConfigurationPropertiesTests.loadWhenHasJsr303ConstraintsShouldFail and
// loadWhenHasJsr303ConstraintsAndValidValuesShouldSucceed): a @Validated properties bean is validated with the
// context's Bean Validation validator, which FlintApplication's lookup finds, and an invalid value fails the binding.
@("validatedConfigurationPropertiesUseTheContextBeanValidationValidator") unittest
{
    import flint.boot : configurationPropertiesValidators;
    import flint.boot.context.properties.bind : BindException, EnvironmentConfigurationPropertiesBinder;
    import flint.boot.context.properties.bind.validation : BindValidationException;
    import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
    import flint.context.support : GenericApplicationContext;
    import flint.engine.aot.any : Any;
    import flint.engine.aot.descriptor : descriptorOf;

    auto context = new GenericApplicationContext;
    context.getDescriptorTable().add(descriptorOf!ValidatedJsr303Properties());
    auto validator = new ValidationAutoConfiguration().defaultValidator(null, context);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    context.getBeanFactory().registerSingleton("defaultValidator", validator);
    context.refresh();
    scope (exit)
        context.close();
    assert(configurationPropertiesValidators(context).length == 1);

    bool bind(string value)
    {
        auto binder = new EnvironmentConfigurationPropertiesBinder(
                [
            cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", [
                ["test.value", value]
            ])
        ]);
        binder.setDescriptors(context.getDescriptorTable());
        binder.setValidatorLookup(() => configurationPropertiesValidators(context));
        auto target = Any.of(new ValidatedJsr303Properties);
        try
            binder.bind("test", target, descriptorOf!ValidatedJsr303Properties());
        catch (BindException failure)
        {
            auto validation = cast(BindValidationException) failure.getCause();
            assert(validation !is null, failure.msg);
            assert(validation.getValidationErrors().getAllErrors().length == 1, validation.msg);
            return false;
        }
        return true;
    }

    assert(!bind("1"));
    assert(bind("5"));
}
