/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/interceptor/AsyncUncaughtExceptionHandler.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/interceptor/ExposeBeanNameAdvisors.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.interceptor;

import flint.aop : Advisor, ProxyMethodInvocation;
import flint.aop.support : DefaultPointcutAdvisor;
import flint.aopalliance.intercept : MethodInterceptor, MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : MemberDescriptorRef;
import flint.engine.aot.objects : objectToString;
import flint.java.lang : ClassCastException, IllegalArgumentException, IllegalStateException;

@safe:

/// Handles a failure from an asynchronous call whose return type cannot convey it.
interface AsyncUncaughtExceptionHandler
{
    /// Receives the exception, the failing method and the arguments used for the call.
    void handleUncaughtException(Throwable failure, MemberDescriptorRef method, Any[] arguments...);
}

/// Advisors that associate a bean name with an invocation.
abstract class ExposeBeanNameAdvisors
{
    private enum beanNameAttribute = "flint.aop.interceptor.ExposeBeanNameAdvisors.BEAN_NAME";
    private enum requiresProxyInvocation = "MethodInvocation is not a Flint ProxyMethodInvocation: ";

    /// Returns the exposed bean name. Throws IllegalStateException if it has not been set.
    static string getBeanName(MethodInvocation invocation)
    {
        auto proxyInvocation = cast(ProxyMethodInvocation) invocation;
        if (proxyInvocation is null)
            throw new IllegalArgumentException(requiresProxyInvocation ~ objectToString(cast(Object) invocation));

        const value = proxyInvocation.getUserAttribute(beanNameAttribute);
        if (value.isNull)
            throw new IllegalStateException(
                    "Cannot get bean name; not set on MethodInvocation: " ~ objectToString(cast(Object) invocation));

        string beanName;
        if (!value.tryGet(beanName))
            throw new ClassCastException("Cannot read bean name from " ~ value.typeName());
        return beanName;
    }

    /// Returns an advisor that exposes the name through the invocation attribute.
    static Advisor createAdvisorWithoutIntroduction(string beanName)
    {
        return new DefaultPointcutAdvisor(new ExposeBeanNameInterceptor(beanName));
    }

    private final static class ExposeBeanNameInterceptor : MethodInterceptor
    {
        private Any beanName;

        this(string beanName)
        {
            this.beanName = Any.of(beanName);
        }

        Any invoke(MethodInvocation invocation)
        {
            auto proxyInvocation = cast(ProxyMethodInvocation) invocation;
            if (proxyInvocation is null)
                throw new IllegalStateException(requiresProxyInvocation ~ objectToString(cast(Object) invocation));
            proxyInvocation.setUserAttribute(beanNameAttribute, beanName);
            return invocation.proceed();
        }
    }
}
