// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/SecurityAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it. Not ported: testJpaCoexistsHappily (Flint has no JPA) and
// testSecurityEvaluationContextExtensionSupport (Spring Data's security extension, which Flint does not have).
module security_autoconfiguration_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.security.autoconfigure : SecurityAutoConfiguration;
import flint.context : ApplicationEvent, ApplicationEventPublisher;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.security.authentication : AuthenticationEventPublisher,
    DefaultAuthenticationEventPublisher, UsernamePasswordAuthenticationToken;
import flint.security.authentication.event : AuthenticationSuccessEvent;

@safe:

private final class RecordingPublisher : ApplicationEventPublisher
{
    ApplicationEvent event;

    void publishEventErased(ApplicationEvent event)
    {
        this.event = event;
    }
}

@("SecurityAutoConfigurationTests.defaultAuthenticationEventPublisherRegistered")
unittest
{
    auto events = new RecordingPublisher;
    AuthenticationEventPublisher publisher = new SecurityAutoConfiguration().authenticationEventPublisher(events);
    assert(cast(DefaultAuthenticationEventPublisher) publisher !is null);

    auto authentication = UsernamePasswordAuthenticationToken.unauthenticated(Any.of("test"), Any.init);
    publisher.publishAuthenticationSuccess(authentication);
    auto success = cast(AuthenticationSuccessEvent) events.event;
    assert(success !is null && success.getAuthentication() is authentication);
}

@("SecurityAutoConfigurationTests.defaultAuthenticationEventPublisherIsConditionalOnMissingBean")
unittest
{
    import std.traits : getUDAs;

    enum conditions = getUDAs!(SecurityAutoConfiguration.authenticationEventPublisher, ConditionalOnMissingBean);
    static assert(conditions.length == 1);
    const types = conditions[0].value;
    assert(types.length == 1 && types[0].name == typeNameOf!AuthenticationEventPublisher);
}
