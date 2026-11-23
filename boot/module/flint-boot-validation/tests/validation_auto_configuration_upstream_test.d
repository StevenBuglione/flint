// Ported from spring-boot v4.2.0: module/spring-boot-validation/src/test/java/org/springframework/boot/validation/autoconfigure/ValidationAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the test methods validation_autoconfiguration_test.d does not port (it holds
// validationAutoConfigurationShouldConfigureDefaultValidator); the auto-configuration's beans are called directly, as
// Flint AOT's generated definitions call them, instead of through an ApplicationContextRunner, and back-off is read
// from the `@ConditionalOnMissingBean` UDAs Flint AOT evaluates. Boot's PrimaryDefaultValidatorPostProcessor waits
// behind FlintPrimaryDefaultValidator, parent contexts behind FlintApplicationContextHierarchy, method validation
// through generated proxies behind FlintMethodValidationProxies, and MethodValidationException behind
// FlintMethodValidationException. Not ported: validationCanBeConfiguredToUseJdkProxy (`spring.aop.proxy-target-class`
// chooses between JDK and CGLIB proxies; Flint AOT generates its proxies).
module validation_auto_configuration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.validation.autoconfigure : ValidationAutoConfiguration, ValidationConfigurationCustomizer;
import flint.jakarta.validation : Configuration;
import std.traits : hasUDA;

@safe:

// Hibernate Validator registers itself as the provider when it is linked.
private alias provider = imported!"flint.hibernate.validator".HibernateValidator;

// The types the `@ConditionalOnMissingBean` of a `@Bean` method names; none means its return type.
private string[] missingBeanTypes(alias method)()
{
    string[] types;
    static foreach (attribute; __traits(getAttributes, method))
        static if (is(typeof(attribute) == ConditionalOnMissingBean))
            foreach (type; attribute.value)
                types ~= type.name;
    return types;
}

@("ValidationAutoConfigurationTests.validationAutoConfigurationWhenUserProvidesValidatorShouldBackOff") unittest
{
    // A user OptionalValidatorFactoryBean is both a Jakarta and a Spring Validator, so either condition backs off.
    static assert(hasUDA!(ValidationAutoConfiguration.defaultValidator, ConditionalOnMissingBean));
    assert(missingBeanTypes!(ValidationAutoConfiguration.defaultValidator)().length == 1);
}

// LIKELY BUG: Boot's defaultValidator backs off for a `jakarta.validation.Validator` bean; Flint's backs off for a
// Spring `flint.validation.Validator`, so a user's Jakarta validator does not replace it, and a user's Spring
// Validator (a custom form or DTO validator) removes the auto-configured LocalValidatorFactoryBean, leaving
// `@Valid` arguments and method validation without Bean Validation.
@("ValidationAutoConfigurationTests.validationAutoConfigurationWhenUserProvidesJsrValidatorShouldBackOff")
unittest
{
    assert(missingBeanTypes!(ValidationAutoConfiguration.defaultValidator)() == [
        "flint.jakarta.validation.Validator"
    ]);
}

@("ValidationAutoConfigurationTests."
        ~ "validationAutoConfigurationWhenUserProvidesSpringValidatorShouldCreateJsrValidator")
unittest
{
    assert(missingBeanTypes!(ValidationAutoConfiguration.defaultValidator)() == [
        "flint.jakarta.validation.Validator"
    ]);
    version (FlintPrimaryDefaultValidator)
        assert(isPrimaryBean!(ValidationAutoConfiguration.defaultValidator));
}

// Boot's PrimaryDefaultValidatorPostProcessor makes `defaultValidator` primary unless another Spring Validator is.
version (FlintPrimaryDefaultValidator)
{
    import flint.boot.validation.autoconfigure : PrimaryDefaultValidatorPostProcessor;

    private bool isPrimaryBean(alias method)()
    {
        return new PrimaryDefaultValidatorPostProcessor().isPrimary(__traits(identifier, method));
    }

    @("ValidationAutoConfigurationTests."
            ~ "validationAutoConfigurationWhenUserProvidesDefaultValidatorShouldNotEnablePrimary")
    unittest
    {
        assert(!isPrimaryBean!(ValidationAutoConfiguration.defaultValidator));
    }

    @("ValidationAutoConfigurationTests."
            ~ "validationAutoConfigurationWhenUserProvidesPrimarySpringValidatorShouldRemovePrimaryFlag")
    unittest
    {
        assert(!isPrimaryBean!(ValidationAutoConfiguration.defaultValidator));
    }
}

// The auto-configuration in a child context of one holding the user's validators.
version (FlintApplicationContextHierarchy)
{
    @("ValidationAutoConfigurationTests."
            ~ "whenUserProvidesSpringValidatorInParentContextThenAutoConfiguredValidatorIsPrimary")
    unittest
    {
        import flint.context.support : GenericApplicationContext;

        auto parent = new GenericApplicationContext;
        auto context = new GenericApplicationContext(parent);
        assert(context.getBeanNamesForTypeIncludingAncestors("flint.validation.Validator").length == 3);
    }

    @("ValidationAutoConfigurationTests."
            ~ "whenUserProvidesPrimarySpringValidatorInParentContextThenAutoConfiguredValidatorIsPrimary")
    unittest
    {
        import flint.context.support : GenericApplicationContext;

        auto parent = new GenericApplicationContext;
        auto context = new GenericApplicationContext(parent);
        assert(context.getBeanNamesForTypeIncludingAncestors("flint.validation.Validator").length == 3);
    }

    @("ValidationAutoConfigurationTests.validationIsEnabledInChildContext") unittest
    {
        import flint.context.support : GenericApplicationContext;

        auto parent = new GenericApplicationContext;
        auto context = new GenericApplicationContext(parent);
        assert(context.getBeansOfType!(imported!"flint.jakarta.validation".Validator)().length == 0);
    }
}

// `@Validated` beans validated through Flint AOT's generated proxies, which a unit test does not have; the
// exclude filter (MethodValidationExcludeFilter) follows with its uses.
version (FlintMethodValidationProxies)
{
    import flint.validation.annotation : Validated;

    /// `SampleService`.
    @Validated class SampleService
    {
        /// `@Size(min = 3, max = 10) String name`.
        void doSomething(@(imported!"flint.jakarta.validation.constraints".Size(3, 10)) string)
        {
        }
    }

    @("ValidationAutoConfigurationTests.validationIsEnabled") unittest
    {
        import flint.jakarta.validation : ConstraintViolationException;
        import std.exception : assertThrown;

        auto service = imported!"flint.engine.aot.proxy".proxyOf!SampleService(new SampleService);
        service.doSomething("Valid");
        assertThrown!ConstraintViolationException(service.doSomething("KO"));
    }

    @("ValidationAutoConfigurationTests.classCanBeExcludedFromValidation") unittest
    {
        import flint.boot.validation : MethodValidationExcludeFilter;

        assert(MethodValidationExcludeFilter.byAnnotation("flint.validation.annotation.Validated") !is null);
    }

    @("ValidationAutoConfigurationTests.validationUsesCglibProxy") unittest
    {
        import flint.jakarta.validation : ConstraintViolationException;
        import std.exception : assertThrown;

        auto service = imported!"flint.engine.aot.proxy".proxyOf!SampleService(new SampleService);
        assertThrown!ConstraintViolationException(service.doSomething("KO"));
    }
}

// Spring's MethodValidationException is not ported: adapting is refused (UnsupportedOperationException), and the
// post-processor has no `adaptConstraintViolations` accessor.
version (FlintMethodValidationException)
{
    @("ValidationAutoConfigurationTests.validationCanBeConfiguredToAdaptConstraintViolations") unittest
    {
        import flint.validation.method : MethodValidationException;

        static assert(is(MethodValidationException : Exception));
    }
}

@("ValidationAutoConfigurationTests.validationUseDefaultAdaptToConstraintViolationsValue") unittest
{
    import flint.context.support : GenericApplicationContext;

    auto context = new GenericApplicationContext;
    const postProcessor = new ValidationAutoConfiguration().methodValidationPostProcessor(context);
    assert(postProcessor !is null);
    version (FlintMethodValidationException)
        assert(!postProcessor.isAdaptConstraintViolations());
}

@("ValidationAutoConfigurationTests.userDefinedMethodValidationPostProcessorTakesPrecedence") unittest
{
    // `testMethodValidationPostProcessor` replaces the auto-configured one.
    static assert(hasUDA!(ValidationAutoConfiguration.methodValidationPostProcessor, ConditionalOnMissingBean));
    assert(missingBeanTypes!(ValidationAutoConfiguration.methodValidationPostProcessor)().length == 0);
}

@("ValidationAutoConfigurationTests.methodValidationPostProcessorValidatorDependencyDoesNotTriggerEarlyInitialization")
unittest
{
    import flint.context.support : GenericApplicationContext;

    // The post-processor asks the context for its validator when it is initialised, not when it is created, so
    // creating it (as BeanPostProcessors are, before other beans) needs no bean from the unrefreshed context.
    auto context = new GenericApplicationContext;
    const postProcessor = new ValidationAutoConfiguration().methodValidationPostProcessor(context);
    assert(postProcessor !is null);
    assert(!context.isActive());
}

// The order customizers are called in.
private final class Calls
{
    string[] names;
}

// Records its calls.
private final class OrderedCustomizer : ValidationConfigurationCustomizer
{
    private string name;
    private Calls calls;

    this(string name, Calls calls) pure nothrow @nogc
    {
        this.name = name;
        this.calls = calls;
    }

    void customize(Configuration)
    {
        calls.names ~= name;
    }
}

// The container hands the customizers in `@Order`: customizerTwo (`@Order(1)`) before customizerOne (`@Order(2)`).
@("ValidationAutoConfigurationTests.configurationCustomizerBeansAreCalledInOrder") unittest
{
    auto calls = new Calls;
    auto customizerOne = new OrderedCustomizer("customizerOne", calls);
    auto customizerTwo = new OrderedCustomizer("customizerTwo", calls);
    auto validator = new ValidationAutoConfiguration().defaultValidator([
        customizerTwo, customizerOne
    ]);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    assert(calls.names == ["customizerTwo", "customizerOne"]);
}
