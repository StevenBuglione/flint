// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/diagnostics/analyzer/
// BindFailureAnalyzerTests.java: the tests boot_tests/enum_binding_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the failure is the Binder's, wrapped in the BeanCreationException a context
// refresh would throw; Java beans are D classes with Java-named accessors; exception types print D's qualified names.
// Not ported: bindExceptionDueToClassNotFoundConversionFailure (binding `Class<?>` by name) and
// bindExceptionWithSuppressedMissingParametersException (javac's `-parameters` flag).
module boot_tests.bind_failure_analyzer_test;

import boot_tests.upstream_support : binderOf, source;
import flint.beans.factory : BeanCreationException;
import flint.boot.context.properties.bind : BindException;
import flint.boot.context.properties.source : ConfigurationPropertySource;
import flint.boot.diagnostics : FailureAnalysis, FailureAnalyzer;
import flint.boot.diagnostics.analyzer : BindFailureAnalyzer;

@safe:

/// `GenericFailureProperties`.
final class GenericFailureProperties
{
    private int value;

    int getValue() const
    {
        return value;
    }

    void setValue(int value)
    {
        this.value = value;
    }
}

/// `NestedFailureProperties`.
final class NestedFailureProperties
{
    private string value;

    string getValue() const
    {
        return value;
    }

    void setValue(string)
    {
        import flint.java.lang : RuntimeException;

        throw new RuntimeException("This is a failure");
    }
}

/// `UnboundElementsFailureProperties`.
final class UnboundElementsFailureProperties
{
    private string[] listValue;

    string[] getListValue()
    {
        return listValue;
    }

    void setListValue(string[] listValue)
    {
        this.listValue = listValue;
    }
}

/// `LoggingProperties`.
final class LoggingProperties
{
    import flint.boot.logging : LogLevel;

    private LogLevel[string] level;

    LogLevel[string] getLevel()
    {
        return level;
    }

    void setLevel(LogLevel[string] level)
    {
        this.level = level;
    }
}

private string failure(string property, string value, string origin, string reason) pure
{
    const valueLine = "\n    Value: \"" ~ value ~ "\"";
    return "Property: " ~ property ~ valueLine ~ "\n    Origin: " ~ origin ~ "\n    Reason: " ~ reason;
}

/// The context refresh's failure binding `T` under `prefix` from `environment`, or `null`.
private BeanCreationException createFailure(T)(string prefix, string[2][] environment...)
{
    try
        binderOf!T([cast(ConfigurationPropertySource) source(environment.dup)]).bind!T(prefix);
    catch (BindException failure)
        return new BeanCreationException(prefix, "Could not bind properties to '" ~ T.stringof ~ "'", failure);
    return null;
}

private FailureAnalysis performAnalysis(T)(string prefix, string[2][] environment...)
{
    auto failure = createFailure!T(prefix, environment);
    assert(failure !is null);
    FailureAnalyzer analyzer = new BindFailureAnalyzer;
    return analyzer.analyze(failure);
}

version (FlintUnboundIndexedElements)
{
    // Gap: binding stops at the first missing index instead of failing with UnboundConfigurationPropertiesException.
    @("analysisForUnboundElementsIsNull") unittest
    {
        const analysis = performAnalysis!UnboundElementsFailureProperties("test.foo",
                ["test.foo.listValue[0]", "hello"], ["test.foo.listValue[2]", "world"]);
        assert(analysis is null);
    }
}

// analysisForValidationExceptionIsNull is in bind_validation_failure_analyzer_test.d, beside the validation setup.

version (FlintPropertySourceOriginText)
{
    // Gap: a map source's default origin reads `test - my.key`, not Boot's `"my.key" from property source "test"`.
    @("bindExceptionDueToOtherFailure") unittest
    {
        import std.algorithm.searching : canFind;

        auto analysis = performAnalysis!GenericFailureProperties("test.foo", [
            "test.foo.value", "alpha"
        ]);
        assert(analysis !is null);
        assert(analysis.getDescription().canFind(failure("test.foo.value", "alpha",
                `"test.foo.value" from property source "test"`,
                "failed to convert java.lang.String to int")), analysis.getDescription());
    }
}

version (FlintBindSetterFailure)
{
    // Gap: an exception thrown by a setter escapes the Binder instead of failing as a BindException for the
    // property.
    @("bindExceptionWithNestedFailureShouldDisplayNestedMessage") unittest
    {
        import std.algorithm.searching : canFind;

        auto analysis = performAnalysis!NestedFailureProperties("test.foo", [
            "test.foo.value", "hello"
        ]);
        assert(analysis !is null);
        assert(analysis.getDescription().canFind(failure("test.foo.value", "hello",
                `"test.foo.value" from property source "test"`,
                "flint.java.lang.RuntimeException: This is a failure")), analysis.getDescription());
    }
}

version (FlintScalarValueForMap)
{
    // Gap: a scalar value under a map's name is ignored (unbound) instead of failing for lack of a String-to-Map
    // converter.
    @("bindExceptionDueToMapConversionFailure") unittest
    {
        import std.algorithm.searching : canFind;

        auto analysis = performAnalysis!LoggingProperties("logging", ["logging.level", "debug"]);
        assert(analysis !is null);
        assert(analysis.getDescription().canFind(failure("logging.level", "debug",
                `"logging.level" from property source "test"`,
                "flint.core.convert.ConverterNotFoundException: No converter found capable of converting from type "
                ~ "[java.lang.String] to type [java.util.Map<java.lang.String, flint.boot.logging.LogLevel>]")),
                analysis.getDescription());
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
