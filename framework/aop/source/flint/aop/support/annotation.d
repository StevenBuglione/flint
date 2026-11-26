/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/annotation/AnnotationClassFilter.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/annotation/AnnotationMatchingPointcut.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.support.annotation;

import flint.aop : ClassFilter, MethodMatcher, Pointcut;
import flint.engine.aot.descriptor : Descriptor;
import flint.engine.aot.objects : objectToHash, objectToString;
import flint.java.classref : ClassRef;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, stringHashCode;

@safe:

/// Selects types bearing the specified annotation.
class AnnotationClassFilter : ClassFilter
{
    mixin JavaObject;

    private string annotationName;
    private bool checkInherited;

    /// Looks for the annotation directly on the target type.
    this(ClassRef annotationType)
    {
        this(annotationType, false);
    }

    /// When checkInherited is true, also considers supertypes and meta-annotations.
    this(ClassRef annotationType, bool checkInherited)
    {
        if (!annotationType.name.length)
            throw new IllegalArgumentException("Annotation type must not be null");
        annotationName = annotationType.name;
        this.checkInherited = checkInherited;
    }

    /// Looks in the target type's generated annotation table.
    bool matches(const Descriptor targetClass)
    {
        if (targetClass is null)
            throw new NullPointerException();
        foreach (ref annotation; targetClass.annotations)
            if (annotation.type == annotationName && (checkInherited
                    || (annotation.aggregateIndex == 0 && annotation.distance == 0)))
                return true;
        return false;
    }

    /// Compares the selected annotation and the hierarchy setting.
    bool equals(Object other)
    {
        auto filter = cast(AnnotationClassFilter) other;
        return filter !is null && filter.annotationName == annotationName && filter.checkInherited == checkInherited;
    }

    /// Hashes the annotation name.
    int hashCode() const nothrow @nogc
    {
        return stringHashCode(annotationName);
    }

    /// Describes this filter and its annotation.
    override string toString() const
    {
        return typeid(this).name ~ ": " ~ annotationName;
    }
}

/// Selects joinpoints by annotation. The class-level configuration applies to all methods of a matching type.
class AnnotationMatchingPointcut : Pointcut
{
    mixin JavaObject;

    private AnnotationClassFilter classFilter;

    /// Matches the annotation directly on the target type.
    this(ClassRef classAnnotationType)
    {
        this(classAnnotationType, false);
    }

    /// Selects a class annotation, optionally through supertypes and meta-annotations.
    this(ClassRef classAnnotationType, bool checkInherited)
    {
        classFilter = new AnnotationClassFilter(classAnnotationType, checkInherited);
    }

    /// Creates a pointcut for a directly declared class annotation.
    static AnnotationMatchingPointcut forClassAnnotation(ClassRef annotationType)
    {
        return new AnnotationMatchingPointcut(annotationType);
    }

    /// Returns the configured class filter.
    ClassFilter getClassFilter()
    {
        return classFilter;
    }

    /// Selects every method of a matching class.
    MethodMatcher getMethodMatcher()
    {
        return MethodMatcher.TRUE;
    }

    /// Compares the filters used by the class-level pointcuts.
    bool equals(Object other)
    {
        auto pointcut = cast(AnnotationMatchingPointcut) other;
        return pointcut !is null && classFilter.equals(pointcut.classFilter);
    }

    /// Hashes the class filter and the common method matcher.
    int hashCode() const nothrow
    {
        return classFilter.hashCode() * 37 + cast(int) objectToHash(cast(Object) MethodMatcher.TRUE);
    }

    /// Describes the class filter and method matcher.
    override string toString() const
    {
        return "AnnotationMatchingPointcut: " ~ classFilter.toString() ~ ", " ~ objectToString(
                cast(Object) MethodMatcher.TRUE);
    }
}
