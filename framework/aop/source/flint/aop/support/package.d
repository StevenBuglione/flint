/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/StaticMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DynamicMethodMatcher.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DynamicMethodMatcherPointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/Pointcuts.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/StaticMethodMatcherPointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/NameMatchMethodPointcut.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/AbstractPointcutAdvisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/AbstractGenericPointcutAdvisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DefaultPointcutAdvisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/DefaultIntroductionAdvisor.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/StaticMethodMatcherPointcutAdvisor.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.support;

public import flint.aop.support.class_filters : ClassFilters, RootClassFilter;
public import flint.aop.support.method_matchers : ComposablePointcut, MethodMatchers;

import flint.aop : Advisor, ClassFilter, DynamicIntroductionAdvice, IntroductionAdvisor,
    IntroductionInfo, MethodMatcher, Pointcut, PointcutAdvisor;
import flint.aop.support.class_filters : ClassPredicate, asClassFilter;
import flint.aopalliance.aop : Advice;
import flint.core : Ordered;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString, statelessInstance;
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
    /// Selects zero-argument methods starting with get and returning a value.
    static Pointcut GETTERS() nothrow @nogc
    {
        return statelessInstance!GetterPointcut();
    }

    /// Selects one-argument methods starting with set and returning void.
    static Pointcut SETTERS() nothrow @nogc
    {
        return statelessInstance!SetterPointcut();
    }

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

private abstract class BeanAccessorPointcut : StaticMethodMatcher, Pointcut
{
    final ClassFilter getClassFilter() nothrow @nogc
    {
        return ClassFilter.TRUE;
    }

    final MethodMatcher getMethodMatcher() nothrow @nogc
    {
        return this;
    }
}

private final class GetterPointcut : BeanAccessorPointcut
{
    override bool matches(const(MethodDescriptor)* method, const Descriptor) nothrow @nogc
    {
        return method.name.length >= 3 && method.name[0 .. 3] == "get" && method.parameters.length == 0
            && method.returnType != "void";
    }

    override string toString() const nothrow @nogc
    {
        return "Pointcuts.GETTERS";
    }
}

private final class SetterPointcut : BeanAccessorPointcut
{
    override bool matches(const(MethodDescriptor)* method, const Descriptor) nothrow @nogc
    {
        return method.name.length >= 3 && method.name[0 .. 3] == "set" && method.parameters.length == 1
            && method.returnType == "void";
    }

    override string toString() const nothrow @nogc
    {
        return "Pointcuts.SETTERS";
    }
}

/// Base class for pointcut advisors with an optional explicit order.
abstract class AbstractPointcutAdvisor : PointcutAdvisor, Ordered
{
    mixin JavaObject;
    mixin Advisor.Defaults;

    private int order;
    private bool orderSet;

    /// Overrides any order supplied by the advice.
    void setOrder(int order)
    {
        this.order = order;
        orderSet = true;
    }

    /// Uses the explicit order, the advice's order, or LOWEST_PRECEDENCE.
    int getOrder()
    {
        if (orderSet)
            return order;
        auto ordered = cast(Ordered) getAdvice();
        return ordered is null ? Ordered.LOWEST_PRECEDENCE : ordered.getOrder();
    }

    /// Compares advice and pointcut values.
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto advisor = cast(PointcutAdvisor) other;
        return advisor !is null && objectEquals(cast(Object) getAdvice(),
                cast(Object) advisor.getAdvice()) && objectEquals(cast(Object) getPointcut(),
                cast(Object) advisor.getPointcut());
    }

    /// The common pointcut-advisor hash.
    int hashCode() const
    {
        enum advisorHash = stringHashCode("flint.aop.PointcutAdvisor");
        return advisorHash;
    }
}

/// Base advisor whose advice can be configured independently of its pointcut.
abstract class AbstractGenericPointcutAdvisor : AbstractPointcutAdvisor
{
    private Advice advice;

    /// Starts without configured advice.
    this()
    {
        advice = Advisor.EMPTY_ADVICE;
    }

    /// Replaces the configured advice.
    void setAdvice(Advice advice)
    {
        this.advice = advice;
    }

    /// Returns the configured advice.
    Advice getAdvice()
    {
        return advice;
    }

    /// Describes this advisor and its advice.
    override string toString()
    {
        return typeid(this).name ~ ": advice [" ~ objectToString(cast(Object) getAdvice()) ~ "]";
    }
}

/// An advisor with a configurable pointcut and advice.
class DefaultPointcutAdvisor : AbstractGenericPointcutAdvisor
{
    private Pointcut pointcut;

    /// Starts with the pointcut that selects every method.
    this()
    {
        pointcut = Pointcut.TRUE;
    }

    /// Uses the given advice for every method.
    this(Advice advice)
    {
        this(Pointcut.TRUE, advice);
    }

    /// Pairs the supplied pointcut with the advice.
    this(Pointcut pointcut, Advice advice)
    {
        this.pointcut = pointcut;
        setAdvice(advice);
    }

    /// Sets the pointcut. Null restores the default pointcut.
    void setPointcut(Pointcut pointcut)
    {
        this.pointcut = pointcut is null ? Pointcut.TRUE : pointcut;
    }

    /// Returns the configured pointcut.
    Pointcut getPointcut()
    {
        return pointcut;
    }

    /// Describes the pointcut and advice.
    override string toString()
    {
        return typeid(this).name ~ ": pointcut [" ~ objectToString(
                cast(Object) getPointcut()) ~ "]; advice [" ~ objectToString(cast(Object) getAdvice()) ~ "]";
    }
}

/// An advisor whose static method matcher is also its pointcut.
abstract class StaticMethodMatcherPointcutAdvisor : StaticMethodMatcherPointcut, PointcutAdvisor, Ordered
{
    mixin Advisor.Defaults;

    private Advice advice;
    private int order = Ordered.LOWEST_PRECEDENCE;

    /// Starts without configured advice.
    this()
    {
        advice = Advisor.EMPTY_ADVICE;
    }

    /// Starts with the supplied advice.
    this(Advice advice)
    {
        if (advice is null)
            throw new IllegalArgumentException("Advice must not be null");
        this.advice = advice;
    }

    /// Sets the order used by this advisor.
    void setOrder(int order)
    {
        this.order = order;
    }

    /// Returns this advisor's order.
    int getOrder()
    {
        return order;
    }

    /// Replaces the configured advice.
    void setAdvice(Advice advice)
    {
        this.advice = advice;
    }

    /// Returns the configured advice.
    Advice getAdvice()
    {
        return advice;
    }

    /// Uses this advisor as the pointcut.
    Pointcut getPointcut()
    {
        return this;
    }
}

/// Configures interfaces supplied by advice and applies to every target class by default.
class DefaultIntroductionAdvisor : IntroductionAdvisor, ClassFilter, Ordered
{
    mixin JavaObject;
    mixin Advisor.Defaults;

    private Advice advice;
    private const(Descriptor)[] interfaces;
    private int order = Ordered.LOWEST_PRECEDENCE;

    /// Uses the interfaces declared by the advice if it provides IntroductionInfo.
    this(Advice advice)
    {
        this(advice, cast(IntroductionInfo) advice);
    }

    /// Uses an explicit interface declaration when supplied.
    this(Advice advice, IntroductionInfo introductionInfo)
    {
        if (advice is null)
            throw new IllegalArgumentException("Advice must not be null");
        this.advice = advice;
        if (introductionInfo is null)
            return;
        const declared = introductionInfo.getInterfaces();
        if (!declared.length)
            throw new IllegalArgumentException(
                    "IntroductionInfo defines no interfaces to introduce: " ~ objectToString(
                    cast(Object) introductionInfo));
        addInterfaces(declared);
    }

    /// Exposes one interface from dynamic introduction advice.
    this(DynamicIntroductionAdvice advice, const Descriptor interfaceType)
    {
        this(advice, cast(IntroductionInfo) null);
        const(Descriptor)[1] declared = [interfaceType];
        addInterfaces(declared[]);
    }

    /// Appends an interface if it is not already configured.
    void addInterface(const Descriptor interfaceType)
    {
        if (interfaceType is null)
            throw new IllegalArgumentException("Interface must not be null");
        if (interfaceType.kind != TypeKind.interface_)
            throw new IllegalArgumentException("Specified class [" ~ interfaceType.name ~ "] must be an interface");
        if (!hasInterface(interfaceType.name))
            interfaces ~= interfaceType;
    }

    /// Returns a snapshot of the interfaces in registration order.
    const(Descriptor)[] getInterfaces()
    {
        // Concatenation copies the array while preserving const on the class references.
        const(Descriptor)[] empty;
        return interfaces ~ empty;
    }

    /// Rejects a configured interface that the dynamic advice cannot supply.
    void validateInterfaces()
    {
        auto dynamicAdvice = cast(DynamicIntroductionAdvice) advice;
        if (dynamicAdvice is null)
            return;
        foreach (interfaceType; interfaces)
            if (!dynamicAdvice.implementsInterface(interfaceType))
                throw new IllegalArgumentException("DynamicIntroductionAdvice [" ~ objectToString(cast(Object) advice)
                        ~ "] does not implement interface [" ~ interfaceType.name ~ "] specified for introduction");
    }

    /// Changes the order of this advisor.
    void setOrder(int order)
    {
        this.order = order;
    }

    /// Returns the configured order, defaulting to LOWEST_PRECEDENCE.
    int getOrder()
    {
        return order;
    }

    /// Returns the advice that supplies the introduction.
    Advice getAdvice()
    {
        return advice;
    }

    /// Uses this advisor as the class filter.
    ClassFilter getClassFilter()
    {
        return this;
    }

    /// Selects any target class.
    bool matches(const Descriptor)
    {
        return true;
    }

    /// Compares the advice and the set of introduced interfaces.
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto advisor = cast(DefaultIntroductionAdvisor) other;
        if (advisor is null || interfaces.length != advisor.interfaces.length
                || !objectEquals(cast(Object) advice, cast(Object) advisor.advice))
            return false;
        foreach (interfaceType; interfaces)
            if (!advisor.hasInterface(interfaceType.name))
                return false;
        return true;
    }

    /// Hashes the advice and the introduced interfaces independently of interface order.
    int hashCode()
    {
        auto hash = cast(int) objectToHash(cast(Object) advice) * 13;
        foreach (interfaceType; interfaces)
            hash += stringHashCode(interfaceType.name);
        return hash;
    }

    /// Describes the advice and introduced interfaces.
    override string toString()
    {
        auto description = typeid(this).name ~ ": advice [" ~ objectToString(cast(Object) advice) ~ "]; interfaces [";
        foreach (index, interfaceType; interfaces)
        {
            if (index)
                description ~= ", ";
            description ~= interfaceType.name;
        }
        return description ~ "]";
    }

    private bool hasInterface(string name) const
    {
        foreach (interfaceType; interfaces)
            if (interfaceType.name == name)
                return true;
        return false;
    }

    private void addInterfaces(scope const(Descriptor)[] declared)
    {
        foreach (interfaceType; declared)
            addInterface(interfaceType);
    }
}
