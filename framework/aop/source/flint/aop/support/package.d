/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/StaticMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DynamicMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DynamicMethodMatcherPointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/Pointcuts.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/StaticMethodMatcherPointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/NameMatchMethodPointcut.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.support;

public import flint.aop.support.class_filters : ClassFilters, RootClassFilter;
public import flint.aop.support.method_matchers : ComposablePointcut, MethodMatchers;

import flint.aop : ClassFilter, MethodMatcher, Pointcut;
import flint.aop.support.class_filters : ClassPredicate, asClassFilter;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException,
    UnsupportedOperationException, stringHashCode;
import flint.util : PatternMatchUtils;

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

/// A pointcut using static method metadata and a configurable class filter.
abstract class StaticMethodMatcherPointcut : StaticMethodMatcher, Pointcut
{
    private ClassFilter classFilter;

    /// Starts with a filter that accepts every class.
    this()
    {
        classFilter = ClassFilter.TRUE;
    }

    /// Selects a class filter for subsequent matching.
    void setClassFilter(ClassFilter filter)
    {
        classFilter = filter;
    }

    /// R9 delegate overload.
    void setClassFilter(ClassPredicate filter)
    {
        setClassFilter(asClassFilter(filter));
    }

    /// Returns the configured class filter.
    ClassFilter getClassFilter()
    {
        return classFilter;
    }

    /// Uses this pointcut's static method test.
    final MethodMatcher getMethodMatcher()
    {
        return this;
    }
}

/// Selects methods by name, including all overloads of a matching name.
class NameMatchMethodPointcut : StaticMethodMatcherPointcut
{
    mixin JavaObject;

    private string[] mappedNames;

    /// Replaces the configured patterns with one pattern.
    void setMappedName(string pattern)
    {
        setMappedNames(pattern);
    }

    /// Replaces the configured patterns with a copy of the supplied list.
    void setMappedNames(scope string[] patterns...)
    {
        mappedNames = patterns.dup;
    }

    /// Adds a pattern while configuring the pointcut.
    NameMatchMethodPointcut addMethodName(string pattern)
    {
        mappedNames ~= pattern;
        return this;
    }

    /// Whether any configured pattern selects the candidate name.
    override bool matches(const(MethodDescriptor)* method, const Descriptor)
    {
        foreach (pattern; mappedNames)
            if (method.name == pattern || isMatch(method.name, pattern))
                return true;
        return false;
    }

    /// Checks Spring's simple wildcard syntax. Subclasses can supply a different matcher.
    protected bool isMatch(string methodName, string pattern)
    {
        return PatternMatchUtils.simpleMatch(pattern, methodName);
    }

    /// Whether the two pointcuts have the same patterns in the same order.
    bool equals(Object other)
    {
        auto pointcut = cast(NameMatchMethodPointcut) other;
        return pointcut !is null && mappedNames == pointcut.mappedNames;
    }

    /// Hashes the ordered patterns using Java's list hash.
    int hashCode() const nothrow @nogc
    {
        int hash = 1;
        foreach (pattern; mappedNames)
            hash = 31 * hash + stringHashCode(pattern);
        return hash;
    }

    /// Describes the pointcut and its patterns.
    override string toString() const
    {
        string text = typeid(this).name ~ ": [";
        foreach (index, pattern; mappedNames)
        {
            if (index != 0)
                text ~= ", ";
            text ~= pattern;
        }
        return text ~ "]";
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
    /// Matches either of the supplied pointcuts.
    static Pointcut union_(Pointcut first, Pointcut second)
    {
        return new ComposablePointcut(first).union_(second);
    }

    /// Matches both of the supplied pointcuts.
    static Pointcut intersection(Pointcut first, Pointcut second)
    {
        return new ComposablePointcut(first).intersection(second);
    }

    /// Test a pointcut against one invocation, checking the class and static method first.
    static bool matches(Pointcut pointcut, const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...)
    {
        if (pointcut is null)
            throw new IllegalArgumentException("Pointcut must not be null");
        if (pointcut is Pointcut.TRUE)
            return true;
        auto filter = pointcut.getClassFilter();
        if (filter is null)
            throw new NullPointerException();
        if (!filter.matches(targetClass))
            return false;
        auto matcher = pointcut.getMethodMatcher();
        return matcher.matches(method, targetClass) && (!matcher.isRuntime()
                || matcher.matches(method, targetClass, args));
    }
}
