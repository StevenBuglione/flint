// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/diagnostics/analyzer/BindFailureAnalyzer.java
// with InvalidConfigurationPropertyNameFailureAnalyzer.java and BindValidationFailureAnalyzer.java from the same directory, and
// core/spring-boot/src/main/java/org/springframework/boot/context/config/ConfigDataNotFoundFailureAnalyzer.java.
// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/diagnostics/analyzer/BeanDefinitionOverrideFailureAnalyzer.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: exception type names are D's fully qualified names, and the override
// action uses the Flint configuration key (R1).

/// `org.springframework.boot.diagnostics.analyzer`: the analyzers Boot core registers.
module flint.boot.diagnostics.analyzer;

import flint.beans.factory.support : BeanDefinitionOverrideException;
import flint.boot.context.config : ConfigDataLocationNotFoundException;
import flint.boot.context.properties.bind : BindException, ConversionFailedException;
import flint.boot.context.properties.source : InvalidConfigurationPropertyNameException;
import flint.boot.diagnostics : AbstractFailureAnalyzer, FailureAnalysis, FailureAnalyzer, causeOf, findCause;

@safe:

/// Explains a bean registration rejected because overriding was disabled.
private final class BeanDefinitionOverrideFailureAnalyzer : AbstractFailureAnalyzer!BeanDefinitionOverrideException
{
    protected override FailureAnalysis analyze(Throwable rootFailure, BeanDefinitionOverrideException cause)
    {
        string description = "The bean '" ~ cause.getBeanName() ~ "'";
        const source = cause.getBeanDefinition().getResourceDescription();
        if (source !is null)
            description ~= ", defined in " ~ source ~ ",";
        description ~= " could not be registered. A bean with that name has already been defined ";
        const existingSource = cause.getExistingDefinition().getResourceDescription();
        if (existingSource !is null)
            description ~= "in " ~ existingSource ~ " ";
        description ~= "and overriding is disabled.";
        enum action = "Consider renaming one of the beans or enabling overriding by setting "
            ~ "flint.main.allow-bean-definition-overriding=true";
        return new FailureAnalysis(description, action, cause);
    }
}

/// Explains a `BindException`: the property, its value and origin, and why it did not bind.
final class BindFailureAnalyzer : AbstractFailureAnalyzer!BindException
{
    protected override FailureAnalysis analyze(Throwable rootFailure, BindException cause)
    {
        import flint.boot.context.properties.bind.validation : BindValidationException;

        // BindValidationFailureAnalyzer explains validation failures.
        if (cast(BindValidationException) causeOf(cause))
            return null;
        string description = cause.getMessage() ~ ":\n";
        if (auto property = cause.getProperty())
        {
            description ~= "\n    Property: " ~ property.getName().toString();
            description ~= "\n    Value: \"" ~ property.getValue() ~ "\"";
            description ~= "\n    Origin: " ~ (property.getOrigin() is null ? "null" : property.getOrigin());
        }
        description ~= "\n    Reason: " ~ reason(cause);
        string action = "Update your application's configuration";
        if (auto conversion = findCause!ConversionFailedException(cause))
        {
            import flint.boot.internal.text : sortStrings;

            auto valid = conversion.getEnumConstants().dup;
            if (valid.length)
            {
                action ~= ". The following values are valid:\n";
                foreach (value; sortStrings(valid))
                    action ~= "\n    " ~ value;
            }
        }
        return new FailureAnalysis(description, action, cause);
    }

    private static string reason(BindException cause)
    {
        auto root = rootCause(causeOf(cause));
        if (auto conversion = findCause!ConversionFailedException(cause))
            return "failed to convert " ~ conversion.getSourceType() ~ " to " ~ conversion.getTargetType() ~ (
                    conversion.getReason().length ? " (caused by " ~ conversion.getReason() ~ ")" : "");
        if (root !is null && root.msg.length)
            return typeAndMessage(root);
        return typeAndMessage(cause);
    }
}

/// Explains a `BindException` caused by a failed validation: each error's property, value and origin, and its
/// message.
final class BindValidationFailureAnalyzer : FailureAnalyzer
{
    /// The analysis of the first `BindValidationException` in `failure`'s causes, or `null`.
    FailureAnalysis analyze(Throwable failure)
    {
        import flint.boot.context.properties.bind.validation : BindValidationException;
        import flint.validation : FieldError;

        auto validation = findCause!BindValidationException(failure);
        if (validation is null)
            return null;
        auto bind = findCause!BindException(failure);
        auto errors = validation.getValidationErrors();
        string description = "Binding to target " ~ (bind is null ? errors.getName()
                .toString() : bind.getTarget()) ~ " failed:\n";
        foreach (error; errors.getAllErrors())
        {
            if (auto fieldError = cast(FieldError) error)
            {
                description ~= "\n    Property: " ~ fieldError.getObjectName() ~ "." ~ fieldError.getField();
                description ~= "\n    Value: \"" ~ rejectedText(fieldError) ~ "\"";
                if (auto property = errors.propertyOf(fieldError))
                {
                    if (property.getOrigin() !is null)
                        description ~= "\n    Origin: " ~ property.getOrigin();
                }
            }
            description ~= "\n    Reason: " ~ error.getDefaultMessage() ~ "\n";
        }
        return new FailureAnalysis(description, "Update your application's configuration", validation);
    }

    private static string rejectedText(imported!"flint.validation".FieldError error)
    {
        import flint.engine.aot.objects : objectToString;

        auto value = error.getRejectedValue();
        if (value.isNull())
            return "null";
        if (value.holds!string)
            return value.get!string;
        if (value.holds!Object)
            return objectToString(value.get!Object);
        return value.toString();
    }
}

/// Explains an invalid configuration property name.
final class InvalidConfigurationPropertyNameFailureAnalyzer
    : AbstractFailureAnalyzer!InvalidConfigurationPropertyNameException
{
    protected override FailureAnalysis analyze(Throwable rootFailure, InvalidConfigurationPropertyNameException cause)
    {
        import flint.engine.aot.text : decodeUtf8, utf8;

        auto bind = findCause!BindException(rootFailure);
        const target = bind is null ? "" : "\n    Bean: " ~ bind.getTarget();
        enum reason = "\n    Reason: Canonical names should be kebab-case ('-' separated), lowercase "
            ~ "alpha-numeric characters and must start with a letter";
        // Each code point quoted, as Boot joins the invalid characters; plain loops, not std.conv/std.algorithm (S-24).
        const characters = cause.getInvalidCharacters();
        string invalid;
        for (size_t index; index < characters.length;)
            invalid ~= (invalid.length ? ", '" : "'") ~ utf8(decodeUtf8(characters, index)) ~ "'";
        const description = "Configuration property name '" ~ cause.getName() ~ "' is not valid:\n"
            ~ "\n    Invalid characters: " ~ invalid ~ target ~ reason;
        const action = "Modify '" ~ cause.getName() ~ "' so that it conforms to the canonical names requirements.";
        return new FailureAnalysis(description, action, cause);
    }
}

/// Explains a missing config data location.
final class ConfigDataNotFoundFailureAnalyzer : AbstractFailureAnalyzer!ConfigDataLocationNotFoundException
{
    protected override FailureAnalysis analyze(Throwable rootFailure, ConfigDataLocationNotFoundException cause)
    {
        const location = cause.getLocation().toString();
        return new FailureAnalysis("Config data location '" ~ location ~ "' does not exist",
                "Check that the value '" ~ location ~ "' is correct, or prefix it with 'optional:'", cause);
    }
}

/// The analyzers Boot core contributes, in Boot's `spring.factories` order.
FailureAnalyzer[] bootFailureAnalyzers()
{
    return [
        cast(FailureAnalyzer) new BeanDefinitionOverrideFailureAnalyzer,
        new InvalidConfigurationPropertyNameFailureAnalyzer, new BindFailureAnalyzer,
        new BindValidationFailureAnalyzer, new ConfigDataNotFoundFailureAnalyzer
    ];
}

private Throwable rootCause(Throwable cause)
{
    auto root = cause;
    while (root !is null && causeOf(root) !is null)
        root = causeOf(root);
    return root;
}

private string typeAndMessage(Throwable failure)
{
    return typeid(failure).name ~ (failure.msg.length ? ": " ~ failure.msg.idup : "");
}
