// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/diagnostics/analyzer/BeanDefinitionOverrideFailureAnalyzerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Flint AOT records supply bean definition resource descriptions.
module boot_tests.bean_definition_override_failure_analyzer_test;

import boot_tests.support : RegisterTests;
import flint.beans.factory.support : BeanDefinitionOverrideException, DefaultListableBeanFactory, RootBeanDefinition;
import flint.boot.diagnostics : FailureAnalyzers;
import flint.boot.diagnostics.analyzer : bootFailureAnalyzers;
import flint.engine.aot.bean : AotBeanDefinition = BeanDefinition;
import flint.java.lang : IllegalStateException;
import std.exception : collectException;

@safe:

@("analyzeBeanDefinitionOverrideException") unittest
{
    auto failure = createFailure("FirstConfiguration", "SecondConfiguration");
    auto analysis = new FailureAnalyzers(bootFailureAnalyzers(), null).analyze(
            new IllegalStateException("Context refresh failed", failure));
    assert(analysis !is null);
    assert(analysis.getDescription() == "The bean 'testBean', defined in SecondConfiguration, could not be registered. "
            ~ "A bean with that name has already been defined in FirstConfiguration and overriding is disabled.");
    assert(analysis.getAction() == "Consider renaming one of the beans or enabling overriding by setting "
            ~ "flint.main.allow-bean-definition-overriding=true");
    assert(analysis.getCause() is failure);
}

@("analyzeBeanDefinitionOverrideExceptionWithDefinitionsWithNoResourceDescription") unittest
{
    auto failure = createFailure(null, null);
    auto analysis = new FailureAnalyzers(bootFailureAnalyzers(), null).analyze(failure);
    assert(analysis !is null);
    assert(analysis.getDescription() == "The bean 'testBean' could not be registered. A bean with that name has already"
            ~ " been defined and overriding is disabled.");
}

private BeanDefinitionOverrideException createFailure(string firstSource, string secondSource)
{
    auto factory = new DefaultListableBeanFactory;
    factory.setAllowBeanDefinitionOverriding(false);
    AotBeanDefinition first;
    first.type = "string";
    first.source = firstSource;
    AotBeanDefinition second = first;
    second.source = secondSource;
    factory.registerBeanDefinition("testBean", new RootBeanDefinition(first));
    auto failure = collectException!BeanDefinitionOverrideException(
            factory.registerBeanDefinition("testBean", new RootBeanDefinition(second)));
    assert(failure !is null);
    return failure;
}

mixin RegisterTests;
