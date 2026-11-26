// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnSingleCandidateTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: supply the test properties through Boot's environment.
module property_relaxed.single_candidate_test;

import flint.boot : ApplicationEnvironment;
import flint.boot.context.config : ConfigDataResult, Profiles;
import flint.boot.context.properties.source : MapConfigurationPropertySource;
import flint.context.support : GenericApplicationContext;
import property_relaxed.single_candidate : Candidate, Consumer;

@safe:

private void expectConsumer(bool enabled)
{
    auto context = new GenericApplicationContext();
    scope (exit)
        context.close();
    const string[2][] properties = [
        ["flint.boot.enableautoconfiguration", "false"],
        ["test.single-candidate", enabled ? "true" : "false"]
    ];
    auto settings = new MapConfigurationPropertySource("test-settings", properties);
    auto profiles = new Profiles(null, ["default"]);
    auto configData = new ConfigDataResult([settings], profiles);
    context.setEnvironment(new ApplicationEnvironment(configData));
    context.deferAotRegistry();
    context.refresh();

    assert(context.containsBean("candidate") == enabled, "candidate provider");
    assert(context.containsBean("consumer") == enabled, "conditional consumer");
    if (enabled)
        assert(context.getBean!Consumer().candidate is context.getBean!Candidate());
}

@("ConditionalOnSingleCandidateTests.singleCandidateNoCandidate")
unittest
{
    expectConsumer(false);
}

@("A single component candidate is injected into the conditional consumer")
unittest
{
    expectConsumer(true);
}
