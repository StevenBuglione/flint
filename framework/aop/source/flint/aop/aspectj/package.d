/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/AspectJPrecedenceInformation.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/AspectJAopUtils.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/AspectInstanceFactory.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/InstantiationModelAwarePointcutAdvisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/SimpleAspectInstanceFactory.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.aspectj;

import flint.aop : Advisor, AfterAdvice, BeforeAdvice, PointcutAdvisor;
import flint.aop.framework : AopConfigException;
import flint.core : Ordered;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor;
import flint.java.lang : IllegalArgumentException;

@safe:

/// Provides an ordered aspect instance independently of the bean factory.
interface AspectInstanceFactory : Ordered
{
    /// Returns the non-null aspect instance (R23).
    Any getAspectInstance();
}

/// Creates a new aspect instance through the class's AOT default constructor.
class SimpleAspectInstanceFactory : AspectInstanceFactory
{
    private const Descriptor aspectClass;

    /// Uses the registered descriptor for the aspect class.
    this(const Descriptor aspectClass)
    {
        if (aspectClass is null)
            throw new IllegalArgumentException("Aspect class must not be null");
        this.aspectClass = aspectClass;
    }

    /// Returns the configured aspect class.
    final const(Descriptor) getAspectClass()
    {
        return aspectClass;
    }

    /// Calls the generated no-argument constructor and preserves any failure as the cause.
    final override Any getAspectInstance()
    {
        if (aspectClass.create is null)
            throw new AopConfigException("No default constructor on aspect class: " ~ aspectClass.name);
        try
            return aspectClass.create();
        catch (Exception failure)
            throw new AopConfigException("Failed to invoke aspect constructor: " ~ aspectClass.name, failure);
    }

    /// Resolves order from the class without creating an aspect.
    override int getOrder()
    {
        return getOrderForAspectClass(aspectClass);
    }

    /// Default precedence for the configured aspect class.
    protected int getOrderForAspectClass(const Descriptor)
    {
        return Ordered.LOWEST_PRECEDENCE;
    }
}

/// A pointcut advisor that exposes the instantiation state of its underlying advice.
interface InstantiationModelAwarePointcutAdvisor : PointcutAdvisor
{
    /// Whether this advisor initializes its advice lazily.
    bool isLazy();

    /// Whether the underlying advice has been instantiated.
    bool isAdviceInstantiated();
}

/// Supplies the metadata for comparing advice and advisors by AspectJ precedence.
interface AspectJPrecedenceInformation : Ordered
{
    /// Returns the name of the aspect declaring the advice.
    string getAspectName();

    /// Returns the advice member's declaration order within the aspect.
    int getDeclarationOrder();

    /// Whether the advice runs before the join point.
    bool isBeforeAdvice();

    /// Whether the advice is a form of after advice.
    bool isAfterAdvice();
}

/// Inspects AspectJ advisors and the advice they carry.
abstract class AspectJAopUtils
{
    /// Whether this advisor provides a form of before advice.
    static bool isBeforeAdvice(Advisor advisor)
    {
        if (auto precedence = getAspectJPrecedenceInformationFor(advisor))
            return precedence.isBeforeAdvice();
        return cast(BeforeAdvice) advisor.getAdvice() !is null;
    }

    /// Whether this advisor provides a form of after advice.
    static bool isAfterAdvice(Advisor advisor)
    {
        if (auto precedence = getAspectJPrecedenceInformationFor(advisor))
            return precedence.isAfterAdvice();
        return cast(AfterAdvice) advisor.getAdvice() !is null;
    }

    /// Reads advisor metadata without instantiating advice when the advisor supplies it.
    static AspectJPrecedenceInformation getAspectJPrecedenceInformationFor(Advisor advisor)
    {
        if (auto precedence = cast(AspectJPrecedenceInformation) advisor)
            return precedence;
        return cast(AspectJPrecedenceInformation) advisor.getAdvice();
    }
}
