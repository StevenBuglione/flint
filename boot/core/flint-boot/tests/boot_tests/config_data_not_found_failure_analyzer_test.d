// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ConfigDataNotFoundFailureAnalyzerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; a `ConfigDataLocation` is a struct.
module boot_tests.config_data_not_found_failure_analyzer_test;

import flint.boot.context.config : ConfigDataLocation, ConfigDataLocationNotFoundException;
import flint.boot.diagnostics : FailureAnalyzer;
import flint.boot.diagnostics.analyzer : ConfigDataNotFoundFailureAnalyzer;

@safe:

private FailureAnalyzer analyzer()
{
    return new ConfigDataNotFoundFailureAnalyzer;
}

@("analyzeWhenConfigDataLocationNotFoundException") unittest
{
    const location = ConfigDataLocation.of("test");
    auto exception = new ConfigDataLocationNotFoundException(location);
    auto result = analyzer().analyze(exception);
    assert(result !is null);
    assert(result.getDescription() == "Config data location 'test' does not exist");
    assert(result.getAction() == "Check that the value 'test' is correct, or prefix it with 'optional:'");
}

version (FlintConfigDataNotFoundAction)
{
    // Gap: the action suggests the `optional:` prefix even for a location that already has it.
    @("analyzeWhenOptionalConfigDataLocationNotFoundException") unittest
    {
        const location = ConfigDataLocation.of("optional:test");
        auto exception = new ConfigDataLocationNotFoundException(location);
        auto result = analyzer().analyze(exception);
        assert(result !is null);
        assert(result.getDescription() == "Config data location 'optional:test' does not exist");
        assert(result.getAction() == "Check that the value 'optional:test' is correct", result.getAction());
    }
}

version (FlintConfigDataLocationApi)
{
    // Gap: locations carry no origin.
    import flint.boot.origin : Origin;

    /// `TestOrigin`.
    final class TestOrigin : Origin
    {
        private string text;

        /// Part of the upstream test fixture.
        this(string text)
        {
            this.text = text;
        }

        Origin getParent()
        {
            return null;
        }

        override string toString() const
        {
            return text;
        }
    }

    @("analyzeWhenConfigDataLocationWithOriginNotFoundException") unittest
    {
        const location = ConfigDataLocation.of("test").withOrigin(new TestOrigin("origin"));
        auto exception = new ConfigDataLocationNotFoundException(location);
        auto result = analyzer().analyze(exception);
        assert(result !is null);
        assert(result.getDescription() == "Config data location 'test' does not exist");
        assert(result.getAction() == "Check that the value 'test' at origin is correct, or prefix it with 'optional:'");
    }
}

version (FlintConfigDataResourceNotFound)
{
    // Gap: there is no ConfigDataResource or ConfigDataResourceNotFoundException.
    import flint.boot.context.config : ConfigDataResource, ConfigDataResourceNotFoundException;

    /// `TestConfigDataResource`.
    final class TestConfigDataResource : ConfigDataResource
    {
        private string text;

        /// Part of the upstream test fixture.
        this(string text)
        {
            this.text = text;
        }

        override string toString() const
        {
            return text;
        }
    }

    @("analyzeWhenConfigDataResourceNotFoundException") unittest
    {
        auto resource = new TestConfigDataResource("myresource");
        auto exception = new ConfigDataResourceNotFoundException(resource);
        auto result = analyzer().analyze(exception);
        assert(result !is null);
        assert(result.getDescription() == "Config data resource 'myresource' does not exist");
        assert(result.getAction() == "Check that the value is correct");
    }

    @("analyzeWhenConfigDataResourceWithLocationNotFoundException") unittest
    {
        const location = ConfigDataLocation.of("test");
        auto resource = new TestConfigDataResource("myresource");
        auto exception = new ConfigDataResourceNotFoundException(resource).withLocation(location);
        auto result = analyzer().analyze(exception);
        assert(result !is null);
        assert(result.getDescription() == "Config data resource 'myresource' via location 'test' does not exist");
        assert(result.getAction() == "Check that the value 'test' is correct, or prefix it with 'optional:'");
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
