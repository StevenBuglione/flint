/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/aop/Advice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/aop/AspectException.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aopalliance.aop;

import flint.java.lang : RuntimeException;

@safe:

/// Marker for advice that can be applied to a joinpoint.
interface Advice
{
}

/// Failure in an aspect's execution.
class AspectException : RuntimeException
{
    /// Records the failure message.
    this(string message)
    {
        super(message);
    }

    /// Records the failure message and its cause.
    this(string message, Throwable cause)
    {
        super(message, cause);
    }
}
