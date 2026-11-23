// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/diagnostics/analyzer/BindFailureAnalyzer.java
// with InvalidConfigurationPropertyNameFailureAnalyzer.java from the same directory, and
// core/spring-boot/src/main/java/org/springframework/boot/context/config/ConfigDataNotFoundFailureAnalyzer.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: exception type names are D's fully qualified names.

/// `org.springframework.boot.diagnostics.analyzer`: the analyzers Boot core registers.
module flint.boot.diagnostics.analyzer;

import flint.boot.context.config : ConfigDataLocationNotFoundException;
import flint.boot.context.properties.bind : BindException, ConversionFailedException;
import flint.boot.context.properties.source : InvalidConfigurationPropertyNameException;
import flint.boot.diagnostics : AbstractFailureAnalyzer, FailureAnalysis, FailureAnalyzer, findCause;

@safe:

/// Explains a `BindException`: the property, its value and origin, and why it did not bind.
final class BindFailureAnalyzer : AbstractFailureAnalyzer!BindException
{
    protected override FailureAnalysis analyze(Throwable rootFailure, BindException cause)
    {
        string description = cause.getMessage() ~ ":\n";
        if (auto property = cause.getProperty())
        {
            description ~= "\n    Property: " ~ property.getName().toString();
            description ~= "\n    Value: \"" ~ property.getValue() ~ "\"";
            description ~= "\n    Origin: " ~ (property.getOrigin() is null ? "null" : property.getOrigin());
        }
        description ~= "\n    Reason: " ~ reason(cause);
        return new FailureAnalysis(description, "Update your application's configuration", cause);
    }

    private static string reason(BindException cause)
    {
        auto root = rootCause(cause.next);
        if (auto conversion = findCause!ConversionFailedException(cause))
            return "failed to convert " ~ conversion.getSourceType() ~ " to " ~ conversion.getTargetType() ~ (
                    conversion.getReason().length ? " (caused by " ~ conversion.getReason() ~ ")" : "");
        if (root !is null && root.msg.length)
            return typeAndMessage(root);
        return typeAndMessage(cause);
    }
}

/// Explains an invalid configuration property name.
final class InvalidConfigurationPropertyNameFailureAnalyzer
    : AbstractFailureAnalyzer!InvalidConfigurationPropertyNameException
{
    protected override FailureAnalysis analyze(Throwable rootFailure, InvalidConfigurationPropertyNameException cause)
    {
        import std.algorithm.iteration : map;
        import std.array : join;
        import std.conv : to;

        auto bind = findCause!BindException(rootFailure);
        const target = bind is null ? "" : "\n    Bean: " ~ bind.getTarget();
        enum reason = "\n    Reason: Canonical names should be kebab-case ('-' separated), lowercase "
            ~ "alpha-numeric characters and must start with a letter";
        const invalid = cause.getInvalidCharacters().map!(c => "'" ~ c.to!string ~ "'").join(", ");
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
        cast(FailureAnalyzer) new InvalidConfigurationPropertyNameFailureAnalyzer,
        new BindFailureAnalyzer, new ConfigDataNotFoundFailureAnalyzer
    ];
}

private Throwable rootCause(Throwable cause)
{
    auto root = cause;
    while (root !is null && root.next !is null)
        root = root.next;
    return root;
}

private string typeAndMessage(Throwable failure)
{
    return typeid(failure).name ~ (failure.msg.length ? ": " ~ failure.msg.idup : "");
}
