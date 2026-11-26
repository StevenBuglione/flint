/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/PointcutsTests.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/MethodMatchersTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module pointcut_tests;

import flint.aop : Advisor, ClassFilter, MethodMatcher, Pointcut, PointcutAdvisor;
import flint.aop.support : DynamicMethodMatcherPointcut, Pointcuts, StaticMethodMatcher;
import flint.aopalliance.aop : Advice;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import std.exception : assertThrown;

@safe:

@("MethodMatchersTests.defaultMatchesAll") unittest
{
    auto exceptionType = new Descriptor("java.lang.Exception", TypeKind.class_);
    auto bean = new Descriptor("TestBean", TypeKind.class_);
    auto getMessage = new MethodDescriptor("getMessage", "string");
    auto setAge = new MethodDescriptor("setAge", "void");
    MethodMatcher matcher = MethodMatcher.TRUE;
    assert(matcher.matches(getMessage, exceptionType));
    assert(matcher.matches(setAge, bean));
    assert(!matcher.isRuntime());
    assertThrown!UnsupportedOperationException(matcher.matches(setAge, bean, [Any.of(6)]));
}

@("PointcutsTests.trueCase") unittest
{
    auto bean = new Descriptor("TestBean", TypeKind.class_);
    auto setAge = new MethodDescriptor("setAge", "void");
    auto getAge = new MethodDescriptor("getAge", "int");
    auto absquatulate = new MethodDescriptor("absquatulate", "void");
    assert(Pointcuts.matches(Pointcut.TRUE, setAge, bean, Any.of(6)));
    assert(Pointcuts.matches(Pointcut.TRUE, getAge, bean));
    assert(Pointcuts.matches(Pointcut.TRUE, absquatulate, bean));
    assert(Pointcut.TRUE is Pointcut.TRUE);
    assert(Pointcut.TRUE.getClassFilter() is ClassFilter.TRUE);
    assert(Pointcut.TRUE.getMethodMatcher() is MethodMatcher.TRUE);
}

private final class EnabledFilter : ClassFilter
{
    bool enabled;
    int calls;

    bool matches(const Descriptor targetClass)
    {
        calls++;
        return enabled && targetClass.name == "TestBean";
    }
}

private final class TracedPointcut : DynamicMethodMatcherPointcut
{
    EnabledFilter filter;
    int staticCalls;
    int runtimeCalls;

    this(EnabledFilter filter)
    {
        this.filter = filter;
    }

    override ClassFilter getClassFilter()
    {
        return filter;
    }

    override bool matches(const(MethodDescriptor)* method, const Descriptor targetClass)
    {
        staticCalls++;
        return method.name == "setAge";
    }

    override bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...)
    {
        runtimeCalls++;
        return args.length == 1 && args[0].get!int() > 0;
    }
}

@("Dynamic pointcuts check the class, then the method, then the current arguments") unittest
{
    auto filter = new EnabledFilter;
    auto pointcut = new TracedPointcut(filter);
    auto bean = new Descriptor("TestBean", TypeKind.class_);
    auto setAge = new MethodDescriptor("setAge", "void");
    auto getAge = new MethodDescriptor("getAge", "int");
    assert(!Pointcuts.matches(pointcut, setAge, bean, Any.of(6)));
    assert(filter.calls == 1 && pointcut.staticCalls == 0 && pointcut.runtimeCalls == 0);
    filter.enabled = true;
    assert(!Pointcuts.matches(pointcut, getAge, bean));
    assert(filter.calls == 2 && pointcut.staticCalls == 1 && pointcut.runtimeCalls == 0);
    assert(!Pointcuts.matches(pointcut, setAge, bean, Any.of(-1)));
    assert(Pointcuts.matches(pointcut, setAge, bean, Any.of(6)));
    assert(filter.calls == 4 && pointcut.staticCalls == 3 && pointcut.runtimeCalls == 2);
    assertThrown!IllegalArgumentException(Pointcuts.matches(null, setAge, bean));
}

private final class EmptyPointcutAdvisor : PointcutAdvisor
{
    mixin Advisor.Defaults;

    Advice getAdvice()
    {
        return Advisor.EMPTY_ADVICE;
    }

    Pointcut getPointcut()
    {
        return Pointcut.TRUE;
    }
}

@("Pointcut advisors preserve the default lifecycle and shared empty advice") unittest
{
    PointcutAdvisor advisor = new EmptyPointcutAdvisor;
    assert(advisor.isPerInstance());
    assert(advisor.getAdvice() !is null && advisor.getAdvice() is Advisor.EMPTY_ADVICE);
    assert(advisor.getPointcut() is Pointcut.TRUE);
}

private final class NameMatcher : StaticMethodMatcher
{
    override bool matches(const(MethodDescriptor)* method, const Descriptor targetClass)
    {
        return method.name == "getAge";
    }
}

@("Static matcher subclasses reject the argument-aware overload") unittest
{
    MethodMatcher matcher = new NameMatcher;
    auto getAge = new MethodDescriptor("getAge", "int");
    assert(!matcher.isRuntime() && matcher.matches(getAge, null));
    assertThrown!UnsupportedOperationException(matcher.matches(getAge, null, Any[].init));
}

@("Advice markers and invocation failures preserve the Spring and Alliance contracts") unittest
{
    import flint.aop : AfterAdvice, AopInvocationException, BeforeAdvice, MethodBeforeAdvice, ThrowsAdvice;
    import flint.aopalliance.aop : AspectException;
    import flint.aopalliance.intercept : Interceptor;
    import flint.core : NestedRuntimeException;
    import flint.java.lang : RuntimeException;

    static assert(is(Interceptor : Advice));
    static assert(is(MethodBeforeAdvice : BeforeAdvice));
    static assert(is(ThrowsAdvice : AfterAdvice));

    auto cause = new Exception("target cause");
    RuntimeException aspectFailure = new AspectException("aspect failed", cause);
    NestedRuntimeException callFailure = new AopInvocationException("invocation failed", cause);
    assert(aspectFailure.getMessage() == "aspect failed" && aspectFailure.getCause() is cause);
    assert(callFailure.getMessage() == "invocation failed" && callFailure.getCause() is cause);
    assert((new AspectException("aspect failed")).getCause() is null);
    assert((new AopInvocationException("invocation failed")).getCause() is null);
}
