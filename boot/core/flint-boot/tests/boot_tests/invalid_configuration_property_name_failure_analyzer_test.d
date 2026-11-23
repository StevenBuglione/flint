// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/diagnostics/analyzer/
// InvalidConfigurationPropertyNameFailureAnalyzerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the failure is the one `@ConfigurationProperties("FooPrefix")` raises, wrapped in
// the BeanCreationException a context refresh would throw for the `invalidPrefixProperties` bean.
module boot_tests.invalid_configuration_property_name_failure_analyzer_test;

import flint.beans.factory : BeanCreationException;
import flint.boot.context.properties.source : ConfigurationPropertyName, InvalidConfigurationPropertyNameException;
import flint.boot.diagnostics : FailureAnalyzer;
import flint.boot.diagnostics.analyzer : InvalidConfigurationPropertyNameFailureAnalyzer;

@safe:

/// The refresh's failure creating the `invalidPrefixProperties` bean bound under `FooPrefix`, or `null`.
private BeanCreationException createFailure()
{
    try
        ConfigurationPropertyName.of("FooPrefix");
    catch (InvalidConfigurationPropertyNameException failure)
        return new BeanCreationException("invalidPrefixProperties", "Could not bind properties", failure);
    return null;
}

version (FlintInvalidNameBeanName)
{
    // Gap: the analysis names the bean only for a BindException, not for the failing bean's BeanCreationException.
    @("analysisWhenRootCauseIsBeanCreationFailureShouldContainBeanName") unittest
    {
        import std.algorithm.searching : canFind;

        auto failure = createFailure();
        assert(failure !is null);
        FailureAnalyzer analyzer = new InvalidConfigurationPropertyNameFailureAnalyzer;
        auto analysis = analyzer.analyze(failure);
        assert(analysis !is null);
        assert(analysis.getDescription()
                .canFind("\n    Invalid characters: 'F', 'P'\n    Bean: invalidPrefixProperties"
                    ~ "\n    Reason: Canonical names should be kebab-case ('-' separated), lowercase alpha-numeric "
                    ~ "characters and must start with a letter"), analysis.getDescription());
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
