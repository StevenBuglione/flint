/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/StaticMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DynamicMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DynamicMethodMatcherPointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/Pointcuts.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.support;

import flint.aop : ClassFilter, MethodMatcher, Pointcut;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;

@safe:

/// Base class for matchers whose result depends only on generated type and method metadata.
abstract class StaticMethodMatcher : MethodMatcher
{
    /// Static matchers never inspect individual call arguments.
    final bool isRuntime() nothrow @nogc
    {
        return false;
    }

    /// Whether the target method can receive advice.
    abstract bool matches(const(MethodDescriptor)* method, const Descriptor targetClass);

    /// Throws UnsupportedOperationException because this matcher is static.
    final bool matches(const(MethodDescriptor)*, const Descriptor, Any[]...)
    {
        throw new UnsupportedOperationException("Illegal MethodMatcher usage");
    }
}

/// Base class for matchers that also inspect call arguments.
abstract class DynamicMethodMatcher : MethodMatcher
{
    /// Dynamic matchers inspect call arguments after static matching succeeds.
    final bool isRuntime() nothrow @nogc
    {
        return true;
    }

    /// Defaults to allowing the argument check for every method.
    bool matches(const(MethodDescriptor)*, const Descriptor)
    {
        return true;
    }

    /// Whether the current arguments allow this advice to run.
    abstract bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...);
}

/// A pointcut whose method matcher also inspects call arguments.
abstract class DynamicMethodMatcherPointcut : DynamicMethodMatcher, Pointcut
{
    ClassFilter getClassFilter()
    {
        return ClassFilter.TRUE;
    }

    final MethodMatcher getMethodMatcher()
    {
        return this;
    }
}

/// Utility operations over pointcuts.
abstract class Pointcuts
{
    /// Test a pointcut against one invocation, checking the class and static method first.
    static bool matches(Pointcut pointcut, const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...)
    {
        if (pointcut is null)
            throw new IllegalArgumentException("Pointcut must not be null");
        if (pointcut is Pointcut.TRUE)
            return true;
        if (!pointcut.getClassFilter().matches(targetClass))
            return false;
        auto matcher = pointcut.getMethodMatcher();
        return matcher.matches(method, targetClass) && (!matcher.isRuntime()
                || matcher.matches(method, targetClass, args));
    }
}
