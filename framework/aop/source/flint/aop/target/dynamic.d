/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/target/dynamic/Refreshable.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.target.dynamic;

@safe:

/// A dynamic target that can be reloaded.
interface Refreshable
{
    /// Refreshes the underlying target.
    void refresh();

    /// Returns the number of actual refreshes since startup.
    long getRefreshCount();

    /// Returns the timestamp in epoch milliseconds of the last actual refresh.
    long getLastRefreshTime();
}
