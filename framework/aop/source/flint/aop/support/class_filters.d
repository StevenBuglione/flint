/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/ClassFilters.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/support/RootClassFilter.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.support.class_filters;

import flint.aop : ClassFilter;
import flint.engine.aot.descriptor : Descriptor, TypeKind;
import flint.engine.aot.name : typeNameOf;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, stringHashCode;

@safe:

package(flint.aop.support) alias ClassPredicate = bool delegate(const Descriptor) @safe;

package(flint.aop.support) ClassFilter asClassFilter(ClassPredicate predicate)
{
    return predicate is null ? null : new DelegateClassFilter(predicate);
}

private final class DelegateClassFilter : ClassFilter
{
    private ClassPredicate predicate;

    this(ClassPredicate predicate)
    {
        this.predicate = predicate;
    }

    bool matches(const Descriptor candidate)
    {
        return predicate(candidate);
    }
}

/// Matches a root class or interface and every assignable type (R4).
class RootClassFilter : ClassFilter
{
    mixin JavaObject;

    private string rootName;

    /// Uses the root type's canonical AOT name.
    this(const Descriptor root)
    {
        if (root is null)
            throw new IllegalArgumentException("Class must not be null");
        rootName = root.name;
    }

    /// Matches when the candidate's AOT metadata names the root type as itself or a supertype.
    bool matches(const Descriptor candidate)
    {
        if (candidate is null)
            throw new NullPointerException();
        if (rootName == typeNameOf!Object)
            return candidate.kind != TypeKind.scalar;
        return candidate.isAssignableTo(rootName);
    }

    /// Whether the other filter has the same root type.
    bool equals(Object other)
    {
        auto filter = cast(RootClassFilter) other;
        return filter !is null && rootName == filter.rootName;
    }

    /// Hashes the root type's canonical name.
    int hashCode() const nothrow @nogc
    {
        return stringHashCode(rootName);
    }

    /// Describes the root type.
    override string toString() const
    {
        return "flint.aop.support.RootClassFilter: " ~ rootName;
    }
}

/// Composes class filters without inspecting methods or arguments.
abstract class ClassFilters
{
    /// Matches a candidate if either filter matches it.
    static ClassFilter union_(ClassFilter first, ClassFilter second)
    {
        return combine(first, second, false);
    }

    /// R9 delegate overload.
    static ClassFilter union_(ClassPredicate first, ClassFilter second)
    {
        return union_(asClassFilter(first), second);
    }

    /// R9 delegate overload.
    static ClassFilter union_(ClassFilter first, ClassPredicate second)
    {
        return union_(first, asClassFilter(second));
    }

    /// R9 delegate overload.
    static ClassFilter union_(ClassPredicate first, ClassPredicate second)
    {
        return union_(asClassFilter(first), asClassFilter(second));
    }

    /// Matches a candidate if at least one supplied filter matches it.
    static ClassFilter union_(ClassFilter[] filters)
    {
        return combine(filters, false);
    }

    /// Matches a candidate if both supplied filters match it.
    static ClassFilter intersection(ClassFilter first, ClassFilter second)
    {
        return combine(first, second, true);
    }

    /// R9 delegate overload.
    static ClassFilter intersection(ClassPredicate first, ClassFilter second)
    {
        return intersection(asClassFilter(first), second);
    }

    /// R9 delegate overload.
    static ClassFilter intersection(ClassFilter first, ClassPredicate second)
    {
        return intersection(first, asClassFilter(second));
    }

    /// R9 delegate overload.
    static ClassFilter intersection(ClassPredicate first, ClassPredicate second)
    {
        return intersection(asClassFilter(first), asClassFilter(second));
    }

    /// Matches a candidate if every supplied filter matches it.
    static ClassFilter intersection(ClassFilter[] filters)
    {
        return combine(filters, true);
    }

    /// Inverts the result of the supplied filter.
    static ClassFilter negate(ClassFilter filter)
    {
        if (filter is null)
            throw new IllegalArgumentException("ClassFilter must not be null");
        return new NegatedClassFilter(filter);
    }

    /// R9 delegate overload.
    static ClassFilter negate(ClassPredicate filter)
    {
        return negate(asClassFilter(filter));
    }

    private static ClassFilter combine(ClassFilter first, ClassFilter second, bool requireAll)
    {
        if (first is null)
            throw new IllegalArgumentException("First ClassFilter must not be null");
        if (second is null)
            throw new IllegalArgumentException("Second ClassFilter must not be null");
        return new CompositeClassFilter([first, second], requireAll);
    }

    private static ClassFilter combine(ClassFilter[] filters, bool requireAll)
    {
        if (filters.length == 0)
            throw new IllegalArgumentException("ClassFilter array must not be empty");
        return new CompositeClassFilter(filters, requireAll);
    }
}

private final class CompositeClassFilter : ClassFilter
{
    mixin JavaObject;

    private ClassFilter[] filters;
    private bool requireAll;

    this(ClassFilter[] filters, bool requireAll)
    {
        this.filters = filters;
        this.requireAll = requireAll;
    }

    bool matches(const Descriptor candidate)
    {
        foreach (filter; filters)
        {
            if (filter is null)
                throw new NullPointerException();
            if (filter.matches(candidate) != requireAll)
                return !requireAll;
        }
        return requireAll;
    }

    bool equals(Object other)
    {
        auto filter = cast(CompositeClassFilter) other;
        if (filter is null || filter.requireAll != requireAll || filter.filters.length != filters.length)
            return false;
        foreach (index, current; filters)
            if (!objectEquals(cast(Object) current, cast(Object) filter.filters[index]))
                return false;
        return true;
    }

    int hashCode() nothrow
    {
        int hash = 1;
        foreach (filter; filters)
            hash = 31 * hash + cast(int) objectToHash(cast(Object) filter);
        return hash;
    }

    override string toString()
    {
        string text = requireAll ? "flint.aop.support.ClassFilters.IntersectionClassFilter: ["
            : "flint.aop.support.ClassFilters.UnionClassFilter: [";
        foreach (index, filter; filters)
        {
            if (index != 0)
                text ~= ", ";
            text ~= objectToString(cast(Object) filter);
        }
        return text ~ "]";
    }
}

private final class NegatedClassFilter : ClassFilter
{
    mixin JavaObject;

    private ClassFilter original;

    this(ClassFilter original)
    {
        this.original = original;
    }

    bool matches(const Descriptor candidate)
    {
        return !original.matches(candidate);
    }

    bool equals(Object other)
    {
        auto filter = cast(NegatedClassFilter) other;
        return filter !is null && objectEquals(cast(Object) original, cast(Object) filter.original);
    }

    int hashCode() nothrow
    {
        enum seed = 31 * (31 + stringHashCode("flint.aop.support.ClassFilters.NegateClassFilter"));
        return seed + cast(int) objectToHash(cast(Object) original);
    }

    override string toString()
    {
        return "Negate " ~ objectToString(cast(Object) original);
    }
}
