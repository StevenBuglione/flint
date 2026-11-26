/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/MethodMatchers.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/ComposablePointcut.java
 * Copyright 2002-present the original author or authors.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * Modified by the Flint authors.
 */
module flint.aop.support.method_matchers;

import flint.aop : ClassFilter, IntroductionAwareMethodMatcher, MethodMatcher, Pointcut;
import flint.aop.support.class_filters : ClassFilters, ClassPredicate, asClassFilter;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
import flint.java.lang : IllegalArgumentException, JavaObject, stringHashCode;

@safe:

/// Operations for composing static and dynamic method matchers.
abstract class MethodMatchers
{
    /// Matches a method when either operand matches.
    static MethodMatcher union_(MethodMatcher first, MethodMatcher second)
    {
        return combine(first, second, false);
    }

    /// Matches a method when both operands match.
    static MethodMatcher intersection(MethodMatcher first, MethodMatcher second)
    {
        return combine(first, second, true);
    }

    /// Reverses the result of the supplied matcher.
    static MethodMatcher negate(MethodMatcher matcher)
    {
        if (matcher is null)
            throw new IllegalArgumentException("MethodMatcher must not be null");
        return new NegatedMethodMatcher(matcher);
    }

    /// Applies the introduction-aware static check when the matcher supports it.
    static bool matches(MethodMatcher matcher, const(MethodDescriptor)* method,
            const Descriptor targetClass, bool hasIntroductions)
    {
        if (matcher is null)
            throw new IllegalArgumentException("MethodMatcher must not be null");
        if (auto introduced = cast(IntroductionAwareMethodMatcher) matcher)
            return introduced.matches(method, targetClass, hasIntroductions);
        return matcher.matches(method, targetClass);
    }

    private static MethodMatcher combine(MethodMatcher first, MethodMatcher second, bool both,
            ClassFilter firstFilter = null, ClassFilter secondFilter = null)
    {
        if (first is null)
            throw new IllegalArgumentException("First MethodMatcher must not be null");
        if (second is null)
            throw new IllegalArgumentException("Second MethodMatcher must not be null");
        if (cast(IntroductionAwareMethodMatcher) first !is null || cast(IntroductionAwareMethodMatcher) second !is null)
            return new IntroductionAwarePair(first, second, both, firstFilter, secondFilter);
        return new MatcherPair(first, second, both, firstFilter, secondFilter);
    }
}

private class MatcherPair : MethodMatcher
{
    private MethodMatcher first;
    private MethodMatcher second;
    private ClassFilter firstFilter;
    private ClassFilter secondFilter;
    private bool both;

    this(MethodMatcher first, MethodMatcher second, bool both, ClassFilter firstFilter, ClassFilter secondFilter)
    {
        this.first = first;
        this.second = second;
        this.both = both;
        this.firstFilter = firstFilter;
        this.secondFilter = secondFilter;
    }

    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass)
    {
        const left = (firstFilter is null || firstFilter.matches(targetClass)) && first.matches(method, targetClass);
        if (left != both)
            return left;
        return (secondFilter is null || secondFilter.matches(targetClass)) && second.matches(method, targetClass);
    }

    bool isRuntime()
    {
        return first.isRuntime() || second.isRuntime();
    }

    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...)
    {
        if (!both)
            return first.matches(method, targetClass, args) || second.matches(method, targetClass, args);

        const left = runtimeMatch(first, method, targetClass, args);
        const right = runtimeMatch(second, method, targetClass, args);
        return left && right;
    }

    private static bool runtimeMatch(MethodMatcher matcher, const(MethodDescriptor)* method,
            const Descriptor targetClass, scope Any[] args)
    {
        return matcher.isRuntime() ? matcher.matches(method, targetClass, args) : matcher.matches(method, targetClass);
    }

    override bool opEquals(Object other)
    {
        auto pair = cast(MatcherPair) other;
        return pair !is null && both == pair.both && objectEquals(cast(Object) first,
                cast(Object) pair.first) && objectEquals(cast(Object) second, cast(Object) pair.second)
            && sameFilter(firstFilter, pair.firstFilter) && sameFilter(secondFilter, pair.secondFilter);
    }

    private static bool sameFilter(ClassFilter first, ClassFilter second)
    {
        if (first is null)
            first = ClassFilter.TRUE;
        if (second is null)
            second = ClassFilter.TRUE;
        return objectEquals(cast(Object) first, cast(Object) second);
    }

    override size_t toHash() nothrow
    {
        const firstHash = cast(int) objectToHash(cast(Object) first);
        const secondHash = cast(int) objectToHash(cast(Object) second);
        return cast(uint)(37 * firstHash + secondHash);
    }

    override string toString()
    {
        const introduced = cast(IntroductionAwareMethodMatcher) this !is null;
        string name = "flint.aop.support.MethodMatchers.";
        if (firstFilter !is null)
            name ~= "ClassFilterAware";
        name ~= both ? "Intersection" : "Union";
        if (introduced)
            name ~= "IntroductionAware";
        name ~= "MethodMatcher: ";
        return name ~ operandText(firstFilter, first) ~ ", " ~ operandText(secondFilter, second);
    }

    private static string operandText(ClassFilter filter, MethodMatcher matcher)
    {
        const text = objectToString(cast(Object) matcher);
        return filter is null ? text : objectToString(cast(Object) filter) ~ ", " ~ text;
    }
}

private final class IntroductionAwarePair : MatcherPair, IntroductionAwareMethodMatcher
{
    this(MethodMatcher first, MethodMatcher second, bool both, ClassFilter firstFilter, ClassFilter secondFilter)
    {
        super(first, second, both, firstFilter, secondFilter);
    }

    alias matches = MatcherPair.matches;

    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, bool hasIntroductions)
    {
        const left = (firstFilter is null || firstFilter.matches(targetClass))
            && MethodMatchers.matches(first, method, targetClass, hasIntroductions);
        if (left != both)
            return left;
        return (secondFilter is null || secondFilter.matches(targetClass))
            && MethodMatchers.matches(second, method, targetClass, hasIntroductions);
    }
}

private final class NegatedMethodMatcher : MethodMatcher
{
    private MethodMatcher original;

    this(MethodMatcher original)
    {
        this.original = original;
    }

    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass)
    {
        return !original.matches(method, targetClass);
    }

    bool isRuntime()
    {
        return original.isRuntime();
    }

    bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...)
    {
        return !original.matches(method, targetClass, args);
    }

    override bool opEquals(Object other)
    {
        auto matcher = cast(NegatedMethodMatcher) other;
        return matcher !is null && objectEquals(cast(Object) original, cast(Object) matcher.original);
    }

    override size_t toHash() nothrow
    {
        enum seed = 31 * (31 + stringHashCode("flint.aop.support.MethodMatchers.NegateMethodMatcher"));
        return cast(uint)(seed + cast(int) objectToHash(cast(Object) original));
    }

    override string toString()
    {
        return "Negate " ~ objectToString(cast(Object) original);
    }
}

/// A pointcut with class and method tests that can be composed independently or as pairs.
class ComposablePointcut : Pointcut
{
    mixin JavaObject;

    private ClassFilter classFilter;
    private MethodMatcher methodMatcher;

    /// Starts with the canonical match-all filters.
    this()
    {
        this(ClassFilter.TRUE, MethodMatcher.TRUE);
    }

    /// Copies the supplied pointcut's filters.
    this(Pointcut pointcut)
    {
        if (pointcut is null)
            throw new IllegalArgumentException("Pointcut must not be null");
        classFilter = pointcut.getClassFilter();
        methodMatcher = pointcut.getMethodMatcher();
    }

    /// Starts with a class filter and accepts every method.
    this(ClassFilter classFilter)
    {
        this(classFilter, MethodMatcher.TRUE);
    }

    /// R9 delegate overload.
    this(ClassPredicate classFilter)
    {
        this(asClassFilter(classFilter));
    }

    /// Starts with a method matcher and accepts every class.
    this(MethodMatcher methodMatcher)
    {
        this(ClassFilter.TRUE, methodMatcher);
    }

    /// Starts with the supplied class filter and method matcher.
    this(ClassFilter classFilter, MethodMatcher methodMatcher)
    {
        if (classFilter is null)
            throw new IllegalArgumentException("ClassFilter must not be null");
        if (methodMatcher is null)
            throw new IllegalArgumentException("MethodMatcher must not be null");
        this.classFilter = classFilter;
        this.methodMatcher = methodMatcher;
    }

    /// R9 delegate overload.
    this(ClassPredicate classFilter, MethodMatcher methodMatcher)
    {
        this(asClassFilter(classFilter), methodMatcher);
    }

    /// Accepts classes matching either class filter.
    ComposablePointcut union_(ClassFilter other)
    {
        classFilter = ClassFilters.union_(classFilter, other);
        return this;
    }

    /// R9 delegate overload.
    ComposablePointcut union_(ClassPredicate other)
    {
        return union_(asClassFilter(other));
    }

    /// Accepts classes matching both class filters.
    ComposablePointcut intersection(ClassFilter other)
    {
        classFilter = ClassFilters.intersection(classFilter, other);
        return this;
    }

    /// R9 delegate overload.
    ComposablePointcut intersection(ClassPredicate other)
    {
        return intersection(asClassFilter(other));
    }

    /// Accepts methods matching either method matcher.
    ComposablePointcut union_(MethodMatcher other)
    {
        methodMatcher = MethodMatchers.union_(methodMatcher, other);
        return this;
    }

    /// Accepts methods matching both method matchers.
    ComposablePointcut intersection(MethodMatcher other)
    {
        methodMatcher = MethodMatchers.intersection(methodMatcher, other);
        return this;
    }

    /// Accepts either pointcut while preserving each class and method combination.
    ComposablePointcut union_(Pointcut other)
    {
        if (other is null)
            throw new IllegalArgumentException("Pointcut must not be null");
        auto filter = other.getClassFilter();
        setFilters(ClassFilters.union_(classFilter, filter), MethodMatchers.combine(methodMatcher,
                other.getMethodMatcher(), false, classFilter, filter));
        return this;
    }

    /// Accepts only classes and methods matching both pointcuts.
    ComposablePointcut intersection(Pointcut other)
    {
        if (other is null)
            throw new IllegalArgumentException("Pointcut must not be null");
        setFilters(ClassFilters.intersection(classFilter, other.getClassFilter()),
                MethodMatchers.intersection(methodMatcher, other.getMethodMatcher()));
        return this;
    }

    private void setFilters(ClassFilter filter, MethodMatcher matcher)
    {
        classFilter = filter;
        methodMatcher = matcher;
    }

    /// Returns the composed class filter.
    ClassFilter getClassFilter()
    {
        return classFilter;
    }

    /// Returns the composed method matcher.
    MethodMatcher getMethodMatcher()
    {
        return methodMatcher;
    }

    /// Whether the class filter and method matcher are equal.
    bool equals(Object other)
    {
        auto pointcut = cast(ComposablePointcut) other;
        return pointcut !is null && objectEquals(cast(Object) classFilter, cast(Object) pointcut.classFilter)
            && objectEquals(cast(Object) methodMatcher, cast(Object) pointcut.methodMatcher);
    }

    /// Hashes the composed class filter and method matcher.
    int hashCode() nothrow
    {
        const classHash = cast(int) objectToHash(cast(Object) classFilter);
        const methodHash = cast(int) objectToHash(cast(Object) methodMatcher);
        return 37 * classHash + methodHash;
    }

    /// Describes the two composed filters.
    override string toString()
    {
        const type = typeid(this);
        const name = type is typeid(ComposablePointcut) ? "flint.aop.support.ComposablePointcut" : type.name;
        const filter = objectToString(cast(Object) classFilter);
        return name ~ ": " ~ filter ~ ", " ~ objectToString(cast(Object) methodMatcher);
    }
}
