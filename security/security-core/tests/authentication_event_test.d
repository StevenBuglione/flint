// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/authentication/event/AuthenticationEventTests.java
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
module flint.security.authentication_event_test;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.security.authentication : DisabledException, UsernamePasswordAuthenticationToken;
import flint.security.authentication.event : AbstractAuthenticationEvent,
    AbstractAuthenticationFailureEvent, AuthenticationFailureDisabledEvent, AuthenticationSuccessEvent;
import flint.security.core : Authentication;
import std.exception : collectException;

@safe:

private Authentication request()
{
    auto authentication = UsernamePasswordAuthenticationToken.unauthenticated(Any.of("Principal"),
            Any.of("Credentials"));
    authentication.setDetails(Any.of("127.0.0.1"));
    return authentication;
}

@("testAbstractAuthenticationEvent")
unittest
{
    auto authentication = request();
    AbstractAuthenticationEvent event = new AuthenticationSuccessEvent(authentication);
    assert(event.getAuthentication() is authentication);
    assert(event.getSource() is cast(Object) authentication);
}

@("testAbstractAuthenticationFailureEvent")
unittest
{
    auto authentication = request();
    auto failure = new DisabledException("TEST");
    AbstractAuthenticationFailureEvent event = new AuthenticationFailureDisabledEvent(authentication, failure);
    assert(event.getAuthentication() is authentication);
    assert(event.getException() is failure);
}

@("testRejectsNullAuthentication")
unittest
{
    auto failure = new DisabledException("TEST");
    const error = collectException!IllegalArgumentException(new AuthenticationFailureDisabledEvent(null, failure));
    assert(error !is null && error.msg == "null source");
}

@("testRejectsNullAuthenticationException")
unittest
{
    const error = collectException!IllegalArgumentException(new AuthenticationFailureDisabledEvent(request(), null));
    assert(error !is null && error.msg == "AuthenticationException is required");
}
