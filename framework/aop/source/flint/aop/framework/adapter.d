/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/adapter/AdvisorAdapter.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/adapter/AdvisorAdapterRegistry.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/adapter/MethodBeforeAdviceInterceptor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/adapter/AfterReturningAdviceInterceptor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/adapter/UnknownAdviceTypeException.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.framework.adapter;

import flint.aop : Advisor, AfterAdvice, AfterReturningAdvice, BeforeAdvice, MethodBeforeAdvice;
import flint.aopalliance.aop : Advice;
import flint.aopalliance.intercept : MethodInterceptor, MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.objects : objectToString;
import flint.java.lang : IllegalArgumentException;

@safe:

/// Adapts supported advice into an AOP Alliance interceptor.
interface AdvisorAdapter
{
    /// Whether this adapter can handle the advice.
    bool supportsAdvice(Advice advice);

    /// Creates an interceptor for the advice carried by the advisor.
    MethodInterceptor getInterceptor(Advisor advisor);
}

/// Configures the adapters used by an interception-based AOP framework.
interface AdvisorAdapterRegistry
{
    /// Returns an existing advisor or wraps supported advice in one.
    Advisor wrap(Any advice);

    /// Returns the interceptors for this advisor, independently of its pointcut.
    MethodInterceptor[] getInterceptors(Advisor advisor);

    /// Registers an adapter for an advice type.
    void registerAdvisorAdapter(AdvisorAdapter adapter);
}

/// Runs before advice and then proceeds with the same invocation.
class MethodBeforeAdviceInterceptor : MethodInterceptor, BeforeAdvice
{
    private MethodBeforeAdvice advice;

    /// Wraps the supplied before advice.
    this(MethodBeforeAdvice advice)
    {
        if (advice is null)
            throw new IllegalArgumentException("Advice must not be null");
        this.advice = advice;
    }

    /// Runs the callback with the current invocation and continues the chain.
    Any invoke(MethodInvocation invocation)
    {
        advice.before(invocation.getMethod(), invocation.getArguments(), invocation.getThis().asObject());
        return invocation.proceed();
    }
}

/// Invokes advice after the wrapped method returns successfully.
class AfterReturningAdviceInterceptor : MethodInterceptor, AfterAdvice
{
    private AfterReturningAdvice advice;

    /// Wraps the supplied after-returning advice.
    this(AfterReturningAdvice advice)
    {
        if (advice is null)
            throw new IllegalArgumentException("Advice must not be null");
        this.advice = advice;
    }

    /// Continues the chain, runs the callback and returns its original result.
    Any invoke(MethodInvocation invocation)
    {
        auto result = invocation.proceed();
        advice.afterReturning(result, invocation.getMethod(), invocation.getArguments(),
                invocation.getThis().asObject());
        return result;
    }
}

/// A value that the registry cannot use as advice or an advisor.
class UnknownAdviceTypeException : IllegalArgumentException
{
    /// Reports the unsupported value in the diagnostic.
    this(Any advice)
    {
        auto reference = advice.asObject();
        const description = reference is null ? advice.toString() : objectToString(reference);
        super("Advice object [" ~ description ~ "] is neither a supported subinterface of "
                ~ "[flint.aopalliance.aop.Advice] nor an [flint.aop.Advisor]");
    }

    /// Reports an explicit failure message.
    this(string message)
    {
        super(message);
    }
}
