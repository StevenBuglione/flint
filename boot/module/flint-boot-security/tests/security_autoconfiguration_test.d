// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/SecurityAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it. Not ported: testJpaCoexistsHappily (Flint has no JPA) and
// testSecurityEvaluationContextExtensionSupport (Spring Data's security extension, which Flint does not have).
module security_autoconfiguration_test;

@safe:

// Flint's SecurityAutoConfiguration defines no AuthenticationEventPublisher: Flint's Spring Security has no
// DefaultAuthenticationEventPublisher.
version (FlintAuthenticationEventPublisher)
{
    import flint.boot.security.autoconfigure : SecurityAutoConfiguration;
    import flint.context : ApplicationEventPublisher;
    import flint.security.authentication : AuthenticationEventPublisher, DefaultAuthenticationEventPublisher;

    private final class NoOpApplicationEventPublisher : ApplicationEventPublisher
    {
        void publishEvent(Object)
        {
        }
    }

    @("SecurityAutoConfigurationTests.defaultAuthenticationEventPublisherRegistered")
    unittest
    {
        const AuthenticationEventPublisher publisher = new SecurityAutoConfiguration().authenticationEventPublisher(
                new NoOpApplicationEventPublisher);
        assert(cast(DefaultAuthenticationEventPublisher) publisher !is null);
    }

    @("SecurityAutoConfigurationTests.defaultAuthenticationEventPublisherIsConditionalOnMissingBean")
    unittest
    {
        import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
        import flint.engine.aot.name : typeNameOf;
        import std.traits : getUDAs;

        string[] missing;
        static foreach (condition; getUDAs!(SecurityAutoConfiguration.authenticationEventPublisher,
                ConditionalOnMissingBean))
            foreach (type; condition.value)
                missing ~= type.name;
        assert(missing == [typeNameOf!AuthenticationEventPublisher]);
    }
}
