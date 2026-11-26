/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/scope/ScopedObject.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.scope_;

import flint.aop : RawTargetAccess;
import flint.engine.aot.any : Any;

@safe:

/// Provides access to the target owned by a scoped proxy.
interface ScopedObject : RawTargetAccess
{
    /// Returns the raw target as stored in the current scope.
    Any getTargetObject();

    /// Removes the current target from its scope.
    void removeFromScope();
}
