/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/annotation/AnnotationMatchingPointcutTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module annotation_class_pointcut_tests;

import std.algorithm.searching : canFind;
import std.exception : assertThrown;

import flint.aop : MethodMatcher, Pointcut;
import flint.aop.support : Pointcuts;
import flint.aop.support.annotation : AnnotationClassFilter, AnnotationMatchingPointcut;
import flint.core.annotation : Order;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.objects : objectToString;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

@Order(12)
private class OrderedBase
{
}

private final class OrderedChild : OrderedBase
{
}

@Order(8)
private struct ComposedOrder
{
}

@ComposedOrder()
private final class MetaOrdered
{
}

private final class Unannotated
{
}

@("classLevelPointcuts") unittest
{
    // Class token comparisons do not depend on the annotation's attributes.
    const annotationType = classOf!Order;
    auto first = new AnnotationMatchingPointcut(annotationType, true);
    auto equivalent = new AnnotationMatchingPointcut(annotationType, true);
    auto direct = new AnnotationMatchingPointcut(annotationType);

    foreach (pointcut; [first, equivalent, direct])
    {
        assert(cast(AnnotationClassFilter) pointcut.getClassFilter() !is null);
        assert(pointcut.getMethodMatcher() is MethodMatcher.TRUE);
    }
    assert(objectToString(cast(Object) first.getClassFilter()).canFind(annotationType.name));
    assert(first == equivalent);
    assert(first != direct);
    assert(first.hashCode() == equivalent.hashCode());
    assert(first.hashCode() == direct.hashCode());
    assert(objectToString(first) == objectToString(equivalent));
}

@("Class annotation pointcuts distinguish direct and hierarchy metadata") unittest
{
    Pointcut direct = AnnotationMatchingPointcut.forClassAnnotation(classOf!Order);
    Pointcut hierarchy = new AnnotationMatchingPointcut(classOf!Order, true);

    auto own = descriptorOf!OrderedBase();
    auto inherited = descriptorOf!OrderedChild();
    auto meta = descriptorOf!MetaOrdered();
    auto unrelated = descriptorOf!Unannotated();
    assert(Pointcuts.matches(direct, null, own));
    assert(Pointcuts.matches(hierarchy, null, own));
    assert(!Pointcuts.matches(direct, null, inherited));
    assert(Pointcuts.matches(hierarchy, null, inherited));
    assert(!Pointcuts.matches(direct, null, meta));
    assert(Pointcuts.matches(hierarchy, null, meta));
    assert(!Pointcuts.matches(direct, null, unrelated));
    assert(!Pointcuts.matches(hierarchy, null, unrelated));
}

@("Class annotation pointcuts require an annotation type and a target descriptor") unittest
{
    auto filter = new AnnotationClassFilter(classOf!Order);
    assertThrown!IllegalArgumentException(new AnnotationClassFilter(ClassRef.init));
    assertThrown!IllegalArgumentException(AnnotationMatchingPointcut.forClassAnnotation(ClassRef.init));
    assertThrown!NullPointerException(filter.matches(null));
}
