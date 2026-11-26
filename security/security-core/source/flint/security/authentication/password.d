// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/authentication/password
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

/// Spring Security's compromised-password check contracts.
module flint.security.authentication.password;

import flint.security.core : AuthenticationException;

@safe:

/// Checks a presented password against a compromised-password source.
interface CompromisedPasswordChecker
{
    /// Whether the password is compromised.
    CompromisedPasswordDecision check(string password);
}

/// The result of a compromised-password check.
class CompromisedPasswordDecision
{
    private bool compromised;

    /// A result recording the decision.
    this(bool compromised)
    {
        this.compromised = compromised;
    }

    /// Whether the password is compromised.
    bool isCompromised()
    {
        return compromised;
    }
}

/// A valid password that must be changed because it is compromised.
class CompromisedPasswordException : AuthenticationException
{
    /// A failure with a message and optional cause.
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }
}
