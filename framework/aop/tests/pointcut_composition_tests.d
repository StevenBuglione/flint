/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/MethodMatchersTests.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/ComposablePointcutTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module pointcut_composition_tests;

import flint.aop : ClassFilter, IntroductionAwareMethodMatcher, MethodMatcher, Pointcut;
import flint.aop.support : ComposablePointcut, DynamicMethodMatcher, MethodMatchers,
    NameMatchMethodPointcut, Pointcuts, RootClassFilter;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;

@safe:

private const(MethodDescriptor)* method(string name)
{
    return new MethodDescriptor(name, "void");
}

private MethodMatcher named(string pattern)
{
    return new NameMatchMethodPointcut().addMethodName(pattern);
}

private final class ArgumentMatcher : DynamicMethodMatcher
{
    alias matches = DynamicMethodMatcher.matches;

    private int expected;
    int calls;

    this(int expected)
    {
        this.expected = expected;
    }

    override bool matches(const(MethodDescriptor)*, const Descriptor, Any[] args...)
    {
        calls++;
        return args.length == 1 && args[0].get!int == expected;
    }
}

@("MethodMatchersTests.single") unittest
{
    auto matcher = MethodMatchers.intersection(MethodMatcher.TRUE, named("get*"));
    assert(matcher.matches(method("getMessage"), null));
    assert(!matcher.matches(method("setAge"), null));
}

@("MethodMatchersTests.dynamicAndStaticMethodMatcherIntersection") unittest
{
    auto setAge = method("setAge");
    auto required = new ArgumentMatcher(5);
    auto intersection = MethodMatchers.intersection(MethodMatcher.TRUE, required);
    assert(intersection.isRuntime());
    assert(intersection.matches(setAge, null));
    assert(intersection.matches(setAge, null, [Any.of(5)]));
    intersection = MethodMatchers.intersection(intersection, new ArgumentMatcher(6));
    assert(intersection.isRuntime());
    assert(intersection.matches(setAge, null));
    assert(!intersection.matches(setAge, null, [Any.of(5)]));
    assert(!intersection.matches(setAge, null, [Any.of(6)]));
    assert(required.calls == 3);
}

@("MethodMatchersTests.staticMethodMatcherUnion") unittest
{
    auto either = MethodMatchers.union_(named("get*"), named("set*"));
    assert(!either.isRuntime());
    assert(either.matches(method("setAge"), null));
    assert(either.matches(method("getAge"), null));
    assert(!either.matches(method("absquatulate"), null));
}

@("Dynamic matcher unions short-circuit in registration order") unittest
{
    auto left = new ArgumentMatcher(5);
    auto right = new ArgumentMatcher(6);
    auto matcher = MethodMatchers.union_(left, right);
    auto targetMethod = method("setAge");
    assert(matcher.isRuntime() && matcher.matches(targetMethod, null));
    assert(matcher.matches(targetMethod, null, [Any.of(5)]));
    assert(left.calls == 1 && right.calls == 0);
    assert(matcher.matches(targetMethod, null, [Any.of(6)]));
    assert(left.calls == 2 && right.calls == 1);
    assert(!matcher.matches(targetMethod, null, [Any.of(7)]));
}

@("MethodMatchersTests.unionEquals") unittest
{
    auto plain = cast(Object) MethodMatchers.union_(MethodMatcher.TRUE, MethodMatcher.TRUE);
    auto composed = new ComposablePointcut(MethodMatcher.TRUE).union_(new ComposablePointcut(MethodMatcher.TRUE));
    auto filtered = cast(Object) composed.getMethodMatcher();
    assert(objectEquals(plain, filtered));
    assert(objectToHash(plain) == objectToHash(filtered));
}

@("MethodMatchersTests.negateMethodMatcher") unittest
{
    auto negated = MethodMatchers.negate(named("get*"));
    assert(negated.matches(method("setAge"), null));
    assert(!negated.matches(method("getAge"), null));
}

@("MethodMatchersTests.negateTrueMethodMatcher") unittest
{
    assert(!MethodMatchers.negate(MethodMatcher.TRUE).matches(method("test"), null));
}

@("MethodMatchersTests.negateTrueMethodMatcherAppliedTwice") unittest
{
    assert(MethodMatchers.negate(MethodMatchers.negate(MethodMatcher.TRUE)).matches(method("test"), null));
}

@("MethodMatchersTests.negateIsNotEqualsToOriginalMatcher") unittest
{
    assert(!objectEquals(cast(Object) MethodMatcher.TRUE, cast(Object) MethodMatchers.negate(MethodMatcher.TRUE)));
}

@("MethodMatchersTests.negateOnSameMatcherIsEquals") unittest
{
    auto first = cast(Object) MethodMatchers.negate(MethodMatcher.TRUE);
    auto second = cast(Object) MethodMatchers.negate(MethodMatcher.TRUE);
    assert(objectEquals(first, second));
}

@("MethodMatchersTests.negateHasNotSameHashCodeAsOriginalMatcher") unittest
{
    assert(objectToHash(cast(Object) MethodMatcher.TRUE) != objectToHash(
            cast(Object) MethodMatchers.negate(MethodMatcher.TRUE)));
}

@("MethodMatchersTests.negateOnSameMatcherHasSameHashCode") unittest
{
    auto first = cast(Object) MethodMatchers.negate(MethodMatcher.TRUE);
    auto second = cast(Object) MethodMatchers.negate(MethodMatcher.TRUE);
    assert(objectToHash(first) == objectToHash(second));
}

@("MethodMatchersTests.toStringIncludesRepresentationOfOriginalMatcher") unittest
{
    assert(objectToString(cast(Object) MethodMatchers.negate(MethodMatcher.TRUE)) == "Negate MethodMatcher.TRUE");
}

@("ComposablePointcutTests.matchAll") unittest
{
    auto pointcut = new ComposablePointcut;
    assert(pointcut.getClassFilter() is ClassFilter.TRUE);
    assert(pointcut.getMethodMatcher() is MethodMatcher.TRUE);
    assert(Pointcuts.matches(pointcut, method("hashCode"), null));
}

@("ComposablePointcutTests.filterByClass") unittest
{
    auto object = new Descriptor("object.Object", TypeKind.class_);
    auto exception = new Descriptor("java.lang.Exception", TypeKind.class_);
    auto nested = new Descriptor("flint.core.NestedRuntimeException", TypeKind.class_);
    nested.supertypes = [exception.name];
    auto text = new Descriptor("string", TypeKind.string_);
    auto pointcut = new ComposablePointcut;
    assert(pointcut.getClassFilter().matches(object));
    assert(pointcut.intersection(new RootClassFilter(exception)) is pointcut);
    assert(!pointcut.getClassFilter().matches(object));
    assert(pointcut.getClassFilter().matches(exception));
    pointcut.intersection(new RootClassFilter(nested));
    assert(!pointcut.getClassFilter().matches(exception));
    assert(pointcut.getClassFilter().matches(nested));
    assert(!pointcut.getClassFilter().matches(text));
    pointcut.union_(new RootClassFilter(text));
    assert(!pointcut.getClassFilter().matches(exception));
    assert(pointcut.getClassFilter().matches(nested));
    assert(pointcut.getClassFilter().matches(text));
}

@("ComposablePointcutTests.unionMethodMatcher") unittest
{
    auto pointcut = new ComposablePointcut(ClassFilter.TRUE, named("getAge"));
    assert(!Pointcuts.matches(pointcut, method("absquatulate"), null));
    assert(Pointcuts.matches(pointcut, method("getAge"), null));
    assert(!Pointcuts.matches(pointcut, method("getName"), null));
    assert(pointcut.union_(named("get*")) is pointcut);
    assert(Pointcuts.matches(pointcut, method("getName"), null));
    assert(!Pointcuts.matches(pointcut, method("absquatulate"), null));
    pointcut.union_(named("absquatulate"));
    assert(Pointcuts.matches(pointcut, method("absquatulate"), null));
    assert(Pointcuts.matches(pointcut, method("getAge"), null));
    assert(Pointcuts.matches(pointcut, method("getName"), null));
    assert(!Pointcuts.matches(pointcut, method("setAge"), null));
}

@("ComposablePointcutTests.intersectionMethodMatcher") unittest
{
    auto pointcut = new ComposablePointcut;
    assert(Pointcuts.matches(pointcut, method("absquatulate"), null));
    assert(pointcut.intersection(named("get*")) is pointcut);
    assert(!Pointcuts.matches(pointcut, method("absquatulate"), null));
    assert(Pointcuts.matches(pointcut, method("getAge"), null));
    assert(Pointcuts.matches(pointcut, method("getName"), null));
    pointcut.intersection(named("getAge"));
    assert(Pointcuts.matches(pointcut, method("getAge"), null));
    assert(!Pointcuts.matches(pointcut, method("getName"), null));
}

@("ComposablePointcutTests.equalsAndHashCode") unittest
{
    auto first = new ComposablePointcut;
    auto second = new ComposablePointcut;
    assert(first.equals(second));
    assert(first.hashCode() == second.hashCode());
    first.intersection(named("get*"));
    assert(!first.equals(second));
    assert(first.hashCode() != second.hashCode());
    second.intersection(named("get*"));
    assert(first.equals(second));
    assert(first.hashCode() == second.hashCode());
    first.union_(named("getAge"));
    second.union_(named("getAge"));
    assert(first.equals(second));
    assert(first == second);
    assert(first.hashCode() == second.hashCode());
}

@("A union preserves the original class and method combinations") unittest
{
    auto left = new Descriptor("fixtures.Left", TypeKind.class_);
    auto right = new Descriptor("fixtures.Right", TypeKind.class_);
    auto read = method("read");
    auto write = method("write");
    Pointcut a = new ComposablePointcut(new RootClassFilter(left), named("read"));
    Pointcut b = new ComposablePointcut(new RootClassFilter(right), named("write"));
    auto either = Pointcuts.union_(a, b);
    assert(Pointcuts.matches(either, read, left));
    assert(Pointcuts.matches(either, write, right));
    assert(!Pointcuts.matches(either, write, left));
    assert(!Pointcuts.matches(either, read, right));
    assert(!Pointcuts.matches(a, write, right));
    assert(!Pointcuts.matches(Pointcuts.intersection(a, b), read, left));
}

private final class IntroductionMatcher : IntroductionAwareMethodMatcher
{
    bool matches(const(MethodDescriptor)*, const Descriptor)
    {
        return false;
    }

    bool isRuntime()
    {
        return false;
    }

    bool matches(const(MethodDescriptor)*, const Descriptor, bool introduced)
    {
        return introduced;
    }

    bool matches(const(MethodDescriptor)*, const Descriptor, Any[]...)
    {
        assert(false, "static matcher received call arguments");
    }
}

@("Composition preserves introduction-aware dispatch and operand validation") unittest
{
    auto read = method("read");
    MethodMatcher aware = new IntroductionMatcher;
    auto either = MethodMatchers.union_(named("write"), aware);
    auto both = MethodMatchers.intersection(aware, named("read"));
    assert(!either.matches(read, null) && !both.matches(read, null));
    assert(MethodMatchers.matches(either, read, null, true));
    assert(MethodMatchers.matches(both, read, null, true));
    assert(!MethodMatchers.matches(either, read, null, false));
    assert(!MethodMatchers.matches(both, read, null, false));
    assert(cast(IntroductionAwareMethodMatcher) MethodMatchers.union_(named("read"), named("write")) is null);
    assertThrown!IllegalArgumentException(MethodMatchers.matches(null, read, null, false));
    assertThrown!IllegalArgumentException(MethodMatchers.union_(aware, null));
    assertThrown!IllegalArgumentException(new ComposablePointcut(ClassFilter.NULL));
    assertThrown!IllegalArgumentException(new ComposablePointcut(cast(MethodMatcher) null));
    assertThrown!IllegalArgumentException(new ComposablePointcut(cast(Pointcut) null));
}
