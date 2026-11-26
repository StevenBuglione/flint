// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnSingleCandidateTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: a disabled component gives AOT a static candidate for the no-candidate context.
module property_relaxed.single_candidate;

import flint.boot.autoconfigure.condition : ConditionalOnProperty, ConditionalOnSingleCandidate;
import flint.boot.context.properties : ClassRef;
import flint.context.annotation : Bean, Configuration;
import flint.stereotype : Component;

@safe:

/// A provider that becomes a candidate only when enabled in the test context.
@Component
@ConditionalOnProperty(name: ["test.single-candidate"], havingValue: "true")
final class Candidate
{
}

/// The bean made by the single-candidate configuration.
final class Consumer
{
    /// The provider selected at startup.
    Candidate candidate;

    /// Hold the provider injected by the generated bean definition.
    this(Candidate candidate)
    {
        this.candidate = candidate;
    }
}

/// Registers the consumer only when a candidate is available.
@Configuration(proxyBeanMethods: false)
@ConditionalOnSingleCandidate(ClassRef("property_relaxed.single_candidate.Candidate"))
class OnBeanSingleCandidateConfiguration
{
    /// Registered with the selected candidate when the condition matches.
    @Bean
    Consumer consumer(Candidate candidate)
    {
        return new Consumer(candidate);
    }
}
