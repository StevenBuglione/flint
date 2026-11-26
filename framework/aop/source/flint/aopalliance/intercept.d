/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/Interceptor.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aopalliance.intercept;

import flint.aopalliance.aop : Advice;

@safe:

/// Marker for advice that intercepts a joinpoint.
interface Interceptor : Advice
{
}
