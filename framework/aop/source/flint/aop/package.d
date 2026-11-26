/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/AopInvocationException.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/BeforeAdvice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/AfterAdvice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/AfterReturningAdvice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/MethodBeforeAdvice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/PointcutAdvisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/RawTargetAccess.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/SpringProxy.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/ThrowsAdvice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/TrueClassFilter.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/TrueMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/TruePointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/Advisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/ClassFilter.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/DynamicIntroductionAdvice.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/IntroductionAwareMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/IntroductionInfo.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/MethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/Pointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/TargetClassAware.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop;

import flint.aopalliance.aop : Advice;
import flint.core : NestedRuntimeException;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor;
import flint.engine.aot.objects : statelessInstance;
import flint.java.lang : UnsupportedOperationException;

@safe:

/// Connects advice to the framework's advisor configuration.
interface Advisor
{
    /// Canonical placeholder for unconfigured advice.
    static Advice EMPTY_ADVICE() nothrow @nogc
    {
        return statelessInstance!EmptyAdvice();
    }

    /// Returns the advice used when this advisor applies.
    Advice getAdvice();

    /// Whether this advisor's advice is associated with one target instance.
    bool isPerInstance();

    /// R3 implementation of the Java interface default.
    mixin template Defaults()
    {
        /// By default the advice is associated with an individual target.
        bool isPerInstance()
        {
            return true;
        }
    }
}

private final class EmptyAdvice : Advice
{
}

/// Matches the generated descriptor for a candidate target class (R4).
interface ClassFilter
{
    /// A typed null for overloads that also accept a delegate (R7, D-7).
    enum ClassFilter NULL = null;

    /// Whether this filter selects the target class or interface.
    bool matches(const Descriptor targetClass);

    /// Canonical filter that matches every class.
    static ClassFilter TRUE() nothrow @nogc
    {
        return statelessInstance!TrueClassFilter();
    }
}

private final class TrueClassFilter : ClassFilter
{
    bool matches(const Descriptor) nothrow @nogc
    {
        return true;
    }

    override string toString() const nothrow @nogc
    {
        return "ClassFilter.TRUE";
    }
}

/// Selects a method statically and can additionally test individual calls.
interface MethodMatcher
{
    /// Test the method's AOT metadata and the target class before installing advice (R4).
    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass);

    /// Whether a static match also needs an argument check before the advice runs.
    bool isRuntime();

    /// Test the current arguments immediately before running the advice.
    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...);

    /// Canonical matcher that matches every method statically.
    static MethodMatcher TRUE() nothrow @nogc
    {
        return statelessInstance!TrueMethodMatcher();
    }
}

private final class TrueMethodMatcher : MethodMatcher
{
    bool matches(const(MethodDescriptor)*, const Descriptor) nothrow @nogc
    {
        return true;
    }

    bool isRuntime() nothrow @nogc
    {
        return false;
    }

    bool matches(const(MethodDescriptor)*, const Descriptor, Any[]...)
    {
        throw new UnsupportedOperationException();
    }

    override string toString() const nothrow @nogc
    {
        return "MethodMatcher.TRUE";
    }
}

/// The class and method tests that select joinpoints for advice.
interface Pointcut
{
    ClassFilter getClassFilter();
    MethodMatcher getMethodMatcher();

    /// Canonical pointcut that matches every class and method.
    static Pointcut TRUE() nothrow @nogc
    {
        return statelessInstance!TruePointcut();
    }
}

private final class TruePointcut : Pointcut
{
    ClassFilter getClassFilter() nothrow @nogc
    {
        return ClassFilter.TRUE;
    }

    MethodMatcher getMethodMatcher() nothrow @nogc
    {
        return MethodMatcher.TRUE;
    }

    override string toString() const nothrow @nogc
    {
        return "Pointcut.TRUE";
    }
}

/// An advisor whose pointcut determines when to use its advice.
interface PointcutAdvisor : Advisor
{
    Pointcut getPointcut();
}

/// Matches methods using the target's known introductions as additional static context.
interface IntroductionAwareMethodMatcher : MethodMatcher
{
    /// Whether this method can receive advice given the target's introductions.
    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, bool hasIntroductions);
}

/// Reports the additional interfaces an introduction supplies.
interface IntroductionInfo
{
    /// The AOT descriptors of the interfaces introduced on the proxy.
    const(Descriptor)[] getInterfaces();
}

/// Advice that can supply behavior for an introduced interface.
interface DynamicIntroductionAdvice : Advice
{
    /// Whether the advice implements the described interface.
    bool implementsInterface(const Descriptor interfaceType);
}

/// Exposes the known target type behind a proxy or target source.
interface TargetClassAware
{
    /// Returns the AOT descriptor of the target, or null when the type is unknown.
    const(Descriptor) getTargetClass();
}

/// Marker for advice that runs before a joinpoint.
interface BeforeAdvice : Advice
{
}

/// Marker for advice that runs after a joinpoint.
interface AfterAdvice : Advice
{
}

/// Marker for advice that handles exceptions from a joinpoint.
interface ThrowsAdvice : AfterAdvice
{
}

/// Invoked before the target. Throwing aborts the call.
interface MethodBeforeAdvice : BeforeAdvice
{
    /// Callback before the target method is invoked.
    void before(const(MethodDescriptor)* method, Any[] args, Object target);
}

/// Invoked after a successful return. Throwing propagates a failure to the caller.
interface AfterReturningAdvice : AfterAdvice
{
    /// Callback with the result of a successfully completed call.
    void afterReturning(Any returnValue, const(MethodDescriptor)* method, Any[] args, Object target);
}

/// Marks a proxy created by Flint AOP.
interface FlintProxy
{
}

/// Marks methods that expose the raw target rather than the proxy.
interface RawTargetAccess
{
}

/// Failure while invoking an AOP joinpoint.
class AopInvocationException : NestedRuntimeException
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
