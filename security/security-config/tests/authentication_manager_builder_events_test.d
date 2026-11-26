// Ported from spring-security 7.2.0: config/src/test/java/org/springframework/security/config/annotation/authentication/AuthenticationManagerBuilderTests.java
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
module flint.security.authentication_manager_builder_events_test;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.security.authentication : AuthenticationEventPublisher, UsernamePasswordAuthenticationToken;
import flint.security.config.annotation.authentication.builders : AuthenticationManagerBuilder;
import flint.security.core : Authentication, AuthenticationException;
import std.exception : collectException;

@safe:

private final class RecordingPublisher : AuthenticationEventPublisher
{
    AuthenticationException failure;
    Authentication request;
    size_t failures;
    size_t successes;

    void publishAuthenticationFailure(AuthenticationException exception, Authentication authentication)
    {
        failure = exception;
        request = authentication;
        ++failures;
    }

    void publishAuthenticationSuccess(Authentication authentication)
    {
        ++successes;
    }
}

@("customAuthenticationEventPublisherWithWeb")
unittest
{
    auto publisher = new RecordingPublisher;
    auto builder = new AuthenticationManagerBuilder;
    assert(builder.authenticationEventPublisher(publisher) is builder);
    auto manager = builder.inMemoryAuthentication().and().build();
    auto request = UsernamePasswordAuthenticationToken.unauthenticated(Any.of("user"), Any.of("password"));

    const failure = collectException!AuthenticationException(manager.authenticate(request));
    assert(failure !is null && failure is publisher.failure);
    assert(publisher.request is request && publisher.failures == 1 && publisher.successes == 0);
}

@("AuthenticationManagerBuilder rejects a null event publisher")
unittest
{
    auto builder = new AuthenticationManagerBuilder;
    const invalid = collectException!IllegalArgumentException(builder.authenticationEventPublisher(null));
    assert(invalid !is null && invalid.msg == "AuthenticationEventPublisher cannot be null");
}
