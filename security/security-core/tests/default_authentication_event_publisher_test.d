// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/authentication/DefaultAuthenticationEventPublisherTests.java
/*
 * Copyright 2004-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the Flint authors.
 */
module flint.security.default_authentication_event_publisher_test;

import flint.context : ApplicationEvent, ApplicationEventPublisher, ApplicationEventPublisherAware;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.security.authentication : AccountExpiredException, AuthenticationServiceException,
    BadCredentialsException, CredentialsExpiredException,
    DefaultAuthenticationEventPublisher,
    DisabledException, InternalAuthenticationServiceException,
    LockedException, ProviderNotFoundException, UsernamePasswordAuthenticationToken;
import flint.security.authentication.event : AbstractAuthenticationFailureEvent,
    AuthenticationFailureBadCredentialsEvent,
    AuthenticationFailureCredentialsExpiredEvent, AuthenticationFailureDisabledEvent,
    AuthenticationFailureExpiredEvent,
    AuthenticationFailureLockedEvent,
    AuthenticationFailureProviderNotFoundEvent,
    AuthenticationFailureProxyUntrustedEvent, AuthenticationFailureServiceExceptionEvent, AuthenticationSuccessEvent;
import flint.security.core : Authentication, AuthenticationException;
import flint.security.core.userdetails : UsernameNotFoundException;
import std.exception : collectException;

@safe:

private final class RecordingPublisher : ApplicationEventPublisher
{
    ApplicationEvent[] events;

    void publishEventErased(ApplicationEvent event)
    {
        events ~= event;
    }
}

private Authentication request()
{
    return UsernamePasswordAuthenticationToken.unauthenticated(Any.of("Principal"), Any.of("Credentials"));
}

@("expectedDefaultMappingsAreSatisfied")
unittest
{
    auto publisher = new DefaultAuthenticationEventPublisher;
    auto recorder = new RecordingPublisher;
    publisher.setApplicationEventPublisher(recorder);
    auto authentication = request();
    auto cause = new Exception("Repository unavailable");

    struct Mapping
    {
        AuthenticationException failure;
        TypeInfo_Class eventType;
    }

    Mapping[] cases = [
        Mapping(new BadCredentialsException(""), typeid(AuthenticationFailureBadCredentialsEvent)),
        Mapping(new BadCredentialsException("", cause), typeid(AuthenticationFailureBadCredentialsEvent)),
        Mapping(new UsernameNotFoundException(""), typeid(AuthenticationFailureBadCredentialsEvent)),
        Mapping(new UsernameNotFoundException("", cause), typeid(AuthenticationFailureBadCredentialsEvent)),
        Mapping(new AccountExpiredException(""), typeid(AuthenticationFailureExpiredEvent)),
        Mapping(new AccountExpiredException("", cause), typeid(AuthenticationFailureExpiredEvent)),
        Mapping(new ProviderNotFoundException(""), typeid(AuthenticationFailureProviderNotFoundEvent)),
        Mapping(new DisabledException(""), typeid(AuthenticationFailureDisabledEvent)),
        Mapping(new DisabledException("", cause), typeid(AuthenticationFailureDisabledEvent)),
        Mapping(new LockedException(""), typeid(AuthenticationFailureLockedEvent)),
        Mapping(new LockedException("", cause), typeid(AuthenticationFailureLockedEvent)),
        Mapping(new AuthenticationServiceException(""), typeid(AuthenticationFailureServiceExceptionEvent)),
        Mapping(new AuthenticationServiceException("", cause), typeid(AuthenticationFailureServiceExceptionEvent)),
        Mapping(new CredentialsExpiredException(""), typeid(AuthenticationFailureCredentialsExpiredEvent)),
        Mapping(new CredentialsExpiredException("", cause), typeid(AuthenticationFailureCredentialsExpiredEvent))
    ];
    foreach (i, mapping; cases)
    {
        publisher.publishAuthenticationFailure(mapping.failure, authentication);
        assert(recorder.events.length == i + 1);
        auto event = cast(AbstractAuthenticationFailureEvent) recorder.events[i];
        assert(event !is null && typeid(event) is mapping.eventType);
        assert(event.getAuthentication() is authentication);
        assert(event.getException() is mapping.failure);
    }
}

@("authenticationSuccessIsPublished")
unittest
{
    auto publisher = new DefaultAuthenticationEventPublisher;
    auto recorder = new RecordingPublisher;
    ApplicationEventPublisherAware aware = publisher;
    aware.setApplicationEventPublisher(recorder);
    auto authentication = request();
    publisher.publishAuthenticationSuccess(authentication);

    assert(recorder.events.length == 1);
    auto event = cast(AuthenticationSuccessEvent) recorder.events[0];
    assert(event !is null && event.getAuthentication() is authentication);

    aware.setApplicationEventPublisher(null);
    publisher.publishAuthenticationSuccess(authentication);
    assert(recorder.events.length == 1);
}

@("DefaultAuthenticationEventPublisher matches exact exception classes")
unittest
{
    auto recorder = new RecordingPublisher;
    auto publisher = new DefaultAuthenticationEventPublisher(recorder);
    AuthenticationServiceException internalFailure = new InternalAuthenticationServiceException("Internal failure");
    auto authentication = request();

    class CustomBadCredentials : BadCredentialsException
    {
        this()
        {
            super("Custom failure");
        }
    }

    publisher.publishAuthenticationFailure(internalFailure, authentication);
    publisher.publishAuthenticationFailure(new CustomBadCredentials, authentication);
    assert(recorder.events.length == 0);

    publisher.publishAuthenticationFailure(new AuthenticationServiceException("Service failure"), authentication);
    assert(recorder.events.length == 1);
    assert(cast(AuthenticationFailureServiceExceptionEvent) recorder.events[0]!is null);
}

@("DefaultAuthenticationEventPublisher constructor and null handling")
unittest
{
    auto error = collectException!IllegalArgumentException(new DefaultAuthenticationEventPublisher(null));
    assert(error !is null && error.msg == "applicationEventPublisher cannot be null");

    auto publisher = new DefaultAuthenticationEventPublisher;
    error = collectException!IllegalArgumentException(publisher.publishAuthenticationSuccess(null));
    assert(error !is null && error.msg == "null source");

    auto recorder = new RecordingPublisher;
    publisher.setApplicationEventPublisher(recorder);
    auto failure = new BadCredentialsException("Invalid credentials");
    publisher.publishAuthenticationFailure(failure, null);
    assert(recorder.events.length == 0);

    assert(collectException!NullPointerException(publisher.publishAuthenticationFailure(null, request())) !is null);
    publisher.setApplicationEventPublisher(null);
    publisher.publishAuthenticationSuccess(null);
    publisher.publishAuthenticationFailure(failure, request());
    assert(recorder.events.length == 0);
}

@("AuthenticationFailureProxyUntrustedEvent preserves its source and cause")
unittest
{
    auto authentication = request();
    auto failure = new BadCredentialsException("Untrusted proxy");
    auto event = new AuthenticationFailureProxyUntrustedEvent(authentication, failure);

    assert(event.getAuthentication() is authentication);
    assert(event.getException() is failure);
}
