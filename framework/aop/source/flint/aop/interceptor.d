/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/interceptor/AsyncUncaughtExceptionHandler.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.interceptor;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : MemberDescriptorRef;

@safe:

/// Handles a failure from an asynchronous call whose return type cannot convey it.
interface AsyncUncaughtExceptionHandler
{
    /// Receives the exception, the failing method and the arguments used for the call.
    void handleUncaughtException(Throwable failure, MemberDescriptorRef method, Any[] arguments...);
}
