/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/scope/ScopedObject.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/scope/ScopedProxyUtils.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.scope_;

import flint.aop : RawTargetAccess;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import std.typecons : Nullable;

@safe:

/// Provides access to the target owned by a scoped proxy.
interface ScopedObject : RawTargetAccess
{
    /// Returns the raw target as stored in the current scope.
    Any getTargetObject();

    /// Removes the current target from its scope.
    void removeFromScope();
}

/// Utilities for working with scoped proxies and their target beans.
abstract class ScopedProxyUtils
{
    private enum targetNamePrefix = "scopedTarget.";

    /// Returns the internal name used to register the target bean.
    static string getTargetBeanName(string originalBeanName)
    {
        return targetNamePrefix ~ originalBeanName;
    }

    /// Recovers the public bean name. Throws IllegalArgumentException for a name without the target prefix.
    static string getOriginalBeanName(Nullable!string targetBeanName)
    {
        const name = targetBeanName.isNull ? "null" : targetBeanName.get;
        if (!isScopedTarget(name))
        {
            const message = "bean name '" ~ name ~ "' does not refer to the target of a scoped proxy";
            throw new IllegalArgumentException(message);
        }
        return name[targetNamePrefix.length .. $];
    }

    /// Whether the name refers to a target bean behind a scoped proxy.
    static bool isScopedTarget(scope string beanName) pure nothrow @nogc
    {
        return beanName.length >= targetNamePrefix.length && beanName[0 .. targetNamePrefix.length] == targetNamePrefix;
    }
}
