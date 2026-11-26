/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/Interceptor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/Joinpoint.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/Invocation.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/MethodInvocation.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/ConstructorInvocation.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/MethodInterceptor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/aopalliance/intercept/ConstructorInterceptor.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aopalliance.intercept;

import flint.aopalliance.aop : Advice;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, MemberDescriptorRef, MethodDescriptor;

@safe:

/// Marker for advice that intercepts a joinpoint.
interface Interceptor : Advice
{
}

/// The current joinpoint and its static member metadata.
interface Joinpoint
{
    /// Continues the interceptor chain and returns its result.
    Any proceed();

    /// Returns the target instance, or Any.init if there is none.
    Any getThis();

    /// Identifies the member in its declaring type's published descriptor.
    MemberDescriptorRef getStaticPart();
}

/// A joinpoint that has invocation arguments.
interface Invocation : Joinpoint
{
    /// Returns the current arguments, which an interceptor may update.
    Any[] getArguments();
}

/// The invocation of a method.
interface MethodInvocation : Invocation
{
    /// Returns the method metadata also identified by getStaticPart.
    const(MethodDescriptor)* getMethod();
}

/// The invocation of a constructor.
interface ConstructorInvocation : Invocation
{
    /// Returns the constructor metadata also identified by getStaticPart.
    const(ConstructorDescriptor)* getConstructor();
}

/// Intercepts a method invocation and may continue it through proceed.
interface MethodInterceptor : Interceptor
{
    /// Returns the original or replacement result of the invocation.
    Any invoke(MethodInvocation invocation);
}

/// Intercepts a constructor invocation and may continue it through proceed.
interface ConstructorInterceptor : Interceptor
{
    /// Returns the constructed or replacement object.
    Any construct(ConstructorInvocation invocation);
}
