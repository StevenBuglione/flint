// Ported from spring-security 7.2.0, core/src/test/java/org/springframework/security/authentication/ProviderManagerTests.java
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

module flint.security.provider_manager_events_test;

import flint.engine.aot.any : Any;
import flint.security.authentication : AuthenticationEventPublisher, AuthenticationProvider,
    BadCredentialsException, InternalAuthenticationServiceException,
    LockedException, ProviderManager, ProviderNotFoundException, UsernamePasswordAuthenticationToken;
import flint.security.core : Authentication, AuthenticationException;
import std.exception : collectException;

@safe:

private final class RecordingPublisher : AuthenticationEventPublisher
{
    Authentication success;
    Authentication request;
    AuthenticationException failure;
    size_t successes;
    size_t failures;

    void publishAuthenticationSuccess(Authentication authentication)
    {
        assert(authentication.getCredentials().isNull);
        success = authentication;
        ++successes;
    }

    void publishAuthenticationFailure(AuthenticationException exception, Authentication authentication)
    {
        assert(exception.getAuthenticationRequest() is authentication);
        failure = exception;
        request = authentication;
        ++failures;
    }
}

private final class DecidingProvider : AuthenticationProvider
{
    private AuthenticationException failure;
    size_t calls;

    this(AuthenticationException failure = null)
    {
        this.failure = failure;
    }

    Authentication authenticate(Authentication authentication)
    {
        ++calls;
        if (failure !is null)
            throw failure;
        return UsernamePasswordAuthenticationToken.authenticated(authentication.getPrincipal(),
                authentication.getCredentials(), null);
    }

    bool supports(string)
    {
        return true;
    }
}

private Authentication loginRequest()
{
    return UsernamePasswordAuthenticationToken.unauthenticated(Any.of("user"), Any.of("password"));
}

@("statusExceptionIsPublished")
unittest
{
    auto failure = new LockedException("Locked");
    auto parentProvider = new DecidingProvider;
    auto parent = new ProviderManager(parentProvider);
    auto manager = new ProviderManager([cast(AuthenticationProvider) new DecidingProvider(failure)], parent);
    auto publisher = new RecordingPublisher;
    manager.setAuthenticationEventPublisher(publisher);
    auto request = loginRequest();

    assert(collectException!LockedException(manager.authenticate(request)) is failure);
    assert(publisher.failures == 1 && publisher.failure is failure && publisher.request is request);
    assert(publisher.successes == 0 && parentProvider.calls == 0);
}

@("authenticateWhenFailsInParentAndPublishesThenChildDoesNotPublish")
unittest
{
    auto parentFailure = new BadCredentialsException("Parent rejected credentials");
    auto parent = new ProviderManager(new DecidingProvider(parentFailure));
    auto child = new ProviderManager([
        cast(AuthenticationProvider) new DecidingProvider(new BadCredentialsException("Child rejected credentials"))
    ], parent);
    auto parentPublisher = new RecordingPublisher;
    auto childPublisher = new RecordingPublisher;
    parent.setAuthenticationEventPublisher(parentPublisher);
    child.setAuthenticationEventPublisher(childPublisher);
    auto request = loginRequest();

    assert(collectException!BadCredentialsException(child.authenticate(request)) is parentFailure);
    assert(parentPublisher.failures == 1 && parentPublisher.failure is parentFailure);
    assert(parentPublisher.request is request && parentPublisher.successes == 0);
    assert(childPublisher.successes == 0 && childPublisher.failures == 0);
}

@("ProviderManager publishes success after erasing credentials")
unittest
{
    auto manager = new ProviderManager(new DecidingProvider(new BadCredentialsException("Try next")),
            new DecidingProvider);
    auto publisher = new RecordingPublisher;
    manager.setAuthenticationEventPublisher(publisher);

    const result = manager.authenticate(loginRequest());
    assert(publisher.successes == 1 && publisher.success is result && publisher.failures == 0);
}

@("ProviderManager leaves parent success publication to the parent")
unittest
{
    auto parent = new ProviderManager(new DecidingProvider);
    auto child = new ProviderManager(null, parent);
    auto parentPublisher = new RecordingPublisher;
    auto childPublisher = new RecordingPublisher;
    parent.setAuthenticationEventPublisher(parentPublisher);
    child.setAuthenticationEventPublisher(childPublisher);

    const result = child.authenticate(loginRequest());
    assert(parentPublisher.successes == 1 && parentPublisher.success is result && parentPublisher.failures == 0);
    assert(childPublisher.successes == 0 && childPublisher.failures == 0);
}

@("ProviderManager publishes an internal failure without trying another provider")
unittest
{
    auto failure = new InternalAuthenticationServiceException("Provider unavailable");
    auto laterProvider = new DecidingProvider;
    auto manager = new ProviderManager(new DecidingProvider(failure), laterProvider);
    auto publisher = new RecordingPublisher;
    manager.setAuthenticationEventPublisher(publisher);
    auto request = loginRequest();

    assert(collectException!InternalAuthenticationServiceException(manager.authenticate(request)) is failure);
    assert(publisher.failures == 1 && publisher.failure is failure && publisher.request is request);
    assert(publisher.successes == 0 && laterProvider.calls == 0);
}

@("providerNotFoundFromParentIsIgnored")
unittest
{
    auto failure = new BadCredentialsException("Child rejected credentials");
    auto parent = new ProviderManager(new DecidingProvider(new ProviderNotFoundException("No provider")));
    auto child = new ProviderManager([cast(AuthenticationProvider) new DecidingProvider(failure)], parent);
    auto publisher = new RecordingPublisher;
    child.setAuthenticationEventPublisher(publisher);
    auto request = loginRequest();

    assert(collectException!BadCredentialsException(child.authenticate(request)) is failure);
    assert(publisher.failures == 1 && publisher.failure is failure && publisher.request is request);
    assert(publisher.successes == 0);
}
