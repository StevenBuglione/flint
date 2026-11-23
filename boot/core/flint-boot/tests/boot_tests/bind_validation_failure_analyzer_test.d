// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/diagnostics/analyzer/
// BindValidationFailureAnalyzerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: boot-core's tests have no Bean Validation provider, so the field constraints
// (`@NotNull`, `@Min(5)`) are checked by a Spring `Validator` registered as Boot's `configurationPropertiesValidator`
// (boot-validation's tests cover the JSR-303 path); the failure is EnvironmentConfigurationPropertiesBinder's,
// wrapped in the BeanCreationException a context refresh would throw; Flint's map source origin text is
// `test - test.foo.value` (FlintPropertySourceOriginText). Not ported: the nested `test.foo.nested.bar` constraint
// (nested properties are validated by `@Valid` cascading, which needs Bean Validation).
module boot_tests.bind_validation_failure_analyzer_test;

import boot_tests.upstream_support : source;
import flint.beans.factory : BeanCreationException;
import flint.boot.context.properties.bind : BindException, EnvironmentConfigurationPropertiesBinder;
import flint.boot.context.properties.source : ConfigurationPropertyName, ConfigurationPropertySource;
import flint.boot.diagnostics : FailureAnalysis, FailureAnalyzer;
import flint.boot.diagnostics.analyzer : BindFailureAnalyzer, BindValidationFailureAnalyzer;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.validation : Errors, Validator;
import flint.validation.annotation : Validated;
import std.algorithm.searching : canFind;

@safe:

/// `FieldValidationFailureProperties`: `@NotNull String foo`, `@Min(5) int value`.
@Validated final class FieldValidationFailureProperties
{
    private string foo;
    private int value;

    string getFoo() const
    {
        return foo;
    }

    void setFoo(string foo)
    {
        this.foo = foo;
    }

    int getValue() const
    {
        return value;
    }

    void setValue(int value)
    {
        this.value = value;
    }
}

/// `ObjectErrorFailureProperties`, which a validator rejects as a whole.
@Validated final class ObjectErrorFailureProperties
{
}

/// The `@NotNull` and `@Min(5, "at least five")` constraints, as a Spring validator.
private final class FieldConstraints : Validator
{
    bool supports(string)
    {
        return true;
    }

    void validate(Any target, Errors errors)
    {
        auto properties = cast(FieldValidationFailureProperties) target.get!Object;
        if (properties.getFoo() is null)
            errors.rejectValue("foo", "NotNull", "must not be null");
        if (properties.getValue() < 5)
            errors.rejectValue("value", "Min", "at least five");
    }
}

/// `ObjectValidationFailureConfiguration`'s validator: rejects the object.
private final class ObjectConstraints : Validator
{
    bool supports(string)
    {
        return true;
    }

    void validate(Any, Errors errors)
    {
        errors.reject("test", "This object could not be bound.");
    }
}

/// The context refresh's failure binding `T` under `test.foo`, validated by `validator`.
private BeanCreationException createFailure(T)(Validator validator, string[2][] environment...)
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!T());
    auto binder = new EnvironmentConfigurationPropertiesBinder(
            [cast(ConfigurationPropertySource) source(environment.dup)]);
    binder.setDescriptors(descriptors);
    binder.setValidatorLookup(() => [validator]);
    auto target = Any.of(new T);
    try
        binder.bind("test.foo", target, descriptorOf!T());
    catch (BindException failure)
        return new BeanCreationException("test.foo", "Could not bind properties to '" ~ T.stringof ~ "'", failure);
    return null;
}

private FailureAnalysis performAnalysis(T)(Validator validator, string[2][] environment...)
{
    auto failure = createFailure!T(validator, environment);
    assert(failure !is null);
    FailureAnalyzer analyzer = new BindValidationFailureAnalyzer;
    return analyzer.analyze(failure);
}

private string failure(string property, string value, string reason) pure
{
    return "Property: " ~ property ~ "\n    Value: \"" ~ value ~ "\"\n    Reason: " ~ reason;
}

@("bindExceptionWithFieldErrorsDueToValidationFailure") unittest
{
    auto analysis = performAnalysis!FieldValidationFailureProperties(new FieldConstraints);
    const description = analysis.getDescription();
    assert(description.canFind(failure("test.foo.foo", "null", "must not be null")), description);
    assert(description.canFind(failure("test.foo.value", "0", "at least five")), description);
    assert(description.canFind("Binding to target boot_tests.bind_validation_failure_analyzer_test."
            ~ "FieldValidationFailureProperties failed:"), description);
}

@("bindExceptionWithOriginDueToValidationFailure") unittest
{
    auto analysis = performAnalysis!FieldValidationFailureProperties(new FieldConstraints, [
        "test.foo.value", "4"
    ]);
    assert(analysis.getDescription().canFind("Origin: test - test.foo.value"), analysis.getDescription());
}

@("bindExceptionWithObjectErrorsDueToValidationFailure") unittest
{
    auto analysis = performAnalysis!ObjectErrorFailureProperties(new ObjectConstraints);
    assert(analysis.getDescription().canFind("Reason: This object could not be bound."), analysis.getDescription());
}

@("otherBindExceptionShouldReturnAnalysis") unittest
{
    // A valid object binds without failure, and a binding that is not validated is left to BindFailureAnalyzer.
    assert(createFailure!FieldValidationFailureProperties(new FieldConstraints, [
            "test.foo.foo", "x"
    ], ["test.foo.value", "5"]) is null);
    FailureAnalyzer analyzer = new BindValidationFailureAnalyzer;
    assert(analyzer.analyze(new BeanCreationException("test", "other",
            new BindException(ConfigurationPropertyName.of("test"), "x", null, null))) is null);
}

// BindFailureAnalyzerTests.analysisForValidationExceptionIsNull: the bind failure analyzer leaves validation failures
// to this one.
@("BindFailureAnalyzerTests.analysisForValidationExceptionIsNull") unittest
{
    auto failure = createFailure!FieldValidationFailureProperties(new FieldConstraints);
    FailureAnalyzer analyzer = new BindFailureAnalyzer;
    assert(analyzer.analyze(failure) is null);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
