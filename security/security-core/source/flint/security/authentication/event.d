// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/authentication/event
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
 * Modified by the Flint authors: ported AbstractAuthenticationEvent,
 * AbstractAuthenticationFailureEvent, AuthenticationFailureDisabledEvent,
 * and AuthenticationSuccessEvent.
 */
module flint.security.authentication.event;

import flint.context : ApplicationEvent;
import flint.java.lang : IllegalArgumentException;
import flint.security.core : Authentication, AuthenticationException;

@safe:

/// An application event whose source is the authentication request or result.
abstract class AbstractAuthenticationEvent : ApplicationEvent
{
    /// Create an event for the given authentication.
    this(Authentication authentication)
    {
        if (authentication is null)
            throw new IllegalArgumentException("null source");
        super(cast(Object) authentication);
    }

    /// The authentication that caused the event.
    Authentication getAuthentication() pure nothrow @nogc
    {
        return cast(Authentication) super.getSource();
    }
}

/// An application event signifying an authentication failure.
abstract class AbstractAuthenticationFailureEvent : AbstractAuthenticationEvent
{
    private AuthenticationException exception;

    /// An authentication failure with its original exception.
    this(Authentication authentication, AuthenticationException exception)
    {
        super(authentication);
        if (exception is null)
            throw new IllegalArgumentException("AuthenticationException is required");
        this.exception = exception;
    }

    /// The exception that caused the event.
    AuthenticationException getException() pure nothrow @nogc
    {
        return exception;
    }
}

/// Authentication failed because the account was disabled.
class AuthenticationFailureDisabledEvent : AbstractAuthenticationFailureEvent
{
    /// An authentication failure on a disabled account.
    this(Authentication authentication, AuthenticationException exception)
    {
        super(authentication, exception);
    }
}

/// The application event for successful authentication.
class AuthenticationSuccessEvent : AbstractAuthenticationEvent
{
    /// A successful authentication.
    this(Authentication authentication)
    {
        super(authentication);
    }
}
