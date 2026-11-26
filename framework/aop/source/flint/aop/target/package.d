/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/target/PoolingConfig.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/target/ThreadLocalTargetSourceStats.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.target;

@safe:

/// Configuration and counts for a pooling target source.
interface PoolingConfig
{
    /// Returns the maximum pool size.
    int getMaxSize();

    /// Returns the number of active targets. Throws UnsupportedOperationException if unavailable.
    int getActiveCount();

    /// Returns the number of idle targets. Throws UnsupportedOperationException if unavailable.
    int getIdleCount();
}

/// Statistics for a thread-bound target source.
interface ThreadLocalTargetSourceStats
{
    /// Returns the number of client invocations.
    int getInvocationCount();

    /// Returns the number of hits satisfied by a thread-bound object.
    int getHitCount();

    /// Returns the number of thread-bound objects created.
    int getObjectCount();
}
