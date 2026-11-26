/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/ClassFiltersTests.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/RootClassFilterTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module class_filter_tests;

import flint.aop : ClassFilter;
import flint.aop.support : ClassFilters, RootClassFilter;
import flint.engine.aot.descriptor : Descriptor, TypeKind;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
import std.exception : assertThrown;
import flint.java.lang : IllegalArgumentException;

@safe:

private Descriptor type(string name, string[] supertypes = null, TypeKind kind = TypeKind.class_)
{
    auto descriptor = new Descriptor(name, kind);
    descriptor.supertypes = supertypes;
    return descriptor;
}

@("RootClassFilterTests.matches") unittest
{
    auto exceptionType = type("java.lang.Exception");
    ClassFilter filter = new RootClassFilter(exceptionType);
    assert(filter.matches(exceptionType));
    assert(filter.matches(type("java.lang.RuntimeException", ["java.lang.Exception"])));
    assert(!filter.matches(type("java.lang.Error")));
}

@("RootClassFilterTests.equals") unittest
{
    ClassFilter first = new RootClassFilter(type("java.lang.Exception"));
    ClassFilter second = new RootClassFilter(type("java.lang.Exception"));
    ClassFilter third = new RootClassFilter(type("fixtures.ITestBean", null, TypeKind.interface_));
    assert(objectEquals(cast(Object) first, cast(Object) second));
    assert(!objectEquals(cast(Object) first, cast(Object) third));
}

@("RootClassFilterTests.hashCodeBehavior") unittest
{
    auto first = new RootClassFilter(type("java.lang.Exception"));
    auto second = new RootClassFilter(type("java.lang.Exception"));
    auto third = new RootClassFilter(type("fixtures.ITestBean", null, TypeKind.interface_));
    assert(first.hashCode() == second.hashCode());
    assert(first.hashCode() != third.hashCode());
}

@("RootClassFilterTests.toStringOutput") unittest
{
    auto first = new RootClassFilter(type("java.lang.Exception"));
    auto second = new RootClassFilter(type("java.lang.Exception"));
    assert(first.toString() == "flint.aop.support.RootClassFilter: java.lang.Exception");
    assert(first.toString() == second.toString());
}

@("Object is assignable from erased reference shapes and excludes primitive class tokens") unittest
{
    auto filter = new RootClassFilter(type("object.Object"));
    assert(filter.matches(type("fixtures.ITestBean", null, TypeKind.interface_)));
    assert(filter.matches(type("string", null, TypeKind.string_)));
    assert(filter.matches(type("int[]", null, TypeKind.array)));
    assert(!filter.matches(type("int", null, TypeKind.scalar)));
}

@("ClassFiltersTests.union") unittest
{
    auto exceptionType = type("java.lang.Exception");
    auto interfaceType = type("fixtures.ITestBean", null, TypeKind.interface_);
    auto runtime = type("java.lang.RuntimeException", ["java.lang.Exception"]);
    auto bean = type("fixtures.TestBean", ["fixtures.ITestBean"]);
    auto exceptions = new RootClassFilter(exceptionType);
    auto implementation = new RootClassFilter(interfaceType);
    assert(exceptions.matches(runtime) && !exceptions.matches(bean));
    assert(!implementation.matches(exceptionType) && implementation.matches(bean));

    auto either = ClassFilters.union_(exceptions, implementation);
    assert(either.matches(runtime) && either.matches(bean));
    assert(!either.matches(type("java.lang.Error")));
    assert(objectToString(cast(Object) either) == "flint.aop.support.ClassFilters.UnionClassFilter: "
            ~ "[flint.aop.support.RootClassFilter: java.lang.Exception, "
            ~ "flint.aop.support.RootClassFilter: fixtures.ITestBean]");
}

@("ClassFiltersTests.intersection") unittest
{
    auto exceptionType = type("java.lang.Exception");
    auto nestedType = type("flint.core.NestedRuntimeException", [
        "java.lang.RuntimeException", "java.lang.Exception"
    ]);
    auto runtime = type("java.lang.RuntimeException", ["java.lang.Exception"]);
    auto exceptions = new RootClassFilter(exceptionType);
    auto nested = new RootClassFilter(nestedType);
    assert(exceptions.matches(runtime) && nested.matches(nestedType));

    auto both = ClassFilters.intersection(exceptions, nested);
    assert(!both.matches(runtime) && !both.matches(type("fixtures.TestBean")));
    assert(both.matches(nestedType));
    assert(objectToString(cast(Object) both) == "flint.aop.support.ClassFilters.IntersectionClassFilter: "
            ~ "[flint.aop.support.RootClassFilter: java.lang.Exception, "
            ~ "flint.aop.support.RootClassFilter: flint.core.NestedRuntimeException]");
}

@("ClassFiltersTests.negateClassFilter") unittest
{
    int calls;
    auto text = type("string", null, TypeKind.string_);
    auto negated = ClassFilters.negate((const Descriptor candidate) {
        calls++;
        assert(candidate is text);
        return true;
    });
    assert(!negated.matches(text) && calls == 1);
}

@("ClassFiltersTests.negateTrueClassFilter") unittest
{
    auto negated = ClassFilters.negate(ClassFilter.TRUE);
    assert(!negated.matches(type("string", null, TypeKind.string_)));
    assert(!negated.matches(type("object.Object")));
    assert(!negated.matches(type("int", null, TypeKind.scalar)));
}

@("ClassFiltersTests.negateTrueClassFilterAppliedTwice") unittest
{
    auto filter = ClassFilters.negate(ClassFilters.negate(ClassFilter.TRUE));
    assert(filter.matches(type("string", null, TypeKind.string_)));
    assert(filter.matches(type("object.Object")));
    assert(filter.matches(type("int", null, TypeKind.scalar)));
}

@("ClassFiltersTests.negateIsNotEqualsToOriginalFilter") unittest
{
    auto original = cast(Object) ClassFilter.TRUE;
    auto negated = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    assert(!objectEquals(original, negated));
}

@("ClassFiltersTests.negateOnSameFilterIsEquals") unittest
{
    auto first = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    auto second = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    assert(first !is second && objectEquals(first, second));
}

@("ClassFiltersTests.negateHasNotSameHashCodeAsOriginalFilter") unittest
{
    auto original = cast(Object) ClassFilter.TRUE;
    auto negated = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    assert(objectToHash(original) != objectToHash(negated));
}

@("ClassFiltersTests.negateOnSameFilterHasSameHashCode") unittest
{
    auto first = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    auto second = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    assert(objectToHash(first) == objectToHash(second));
}

@("ClassFiltersTests.toStringIncludesRepresentationOfOriginalFilter") unittest
{
    auto negated = cast(Object) ClassFilters.negate(ClassFilter.TRUE);
    assert(objectToString(negated) == "Negate ClassFilter.TRUE");
}

@("Class filter composition validates empty operands and short circuits in input order") unittest
{
    assertThrown!IllegalArgumentException(new RootClassFilter(null));
    assertThrown!IllegalArgumentException(ClassFilters.union_(ClassFilter[].init));
    assertThrown!IllegalArgumentException(ClassFilters.intersection(ClassFilter[].init));
    assertThrown!IllegalArgumentException(ClassFilters.negate(ClassFilter.NULL));
    assertThrown!IllegalArgumentException(ClassFilters.union_(ClassFilter.NULL, ClassFilter.TRUE));
    assertThrown!IllegalArgumentException(ClassFilters.intersection(ClassFilter.TRUE, ClassFilter.NULL));
    bool delegate(const Descriptor) @safe nullPredicate;
    assertThrown!IllegalArgumentException(ClassFilters.negate(nullPredicate));

    auto descriptor = type("fixtures.Bean");
    int calls;
    auto failIfCalled = (const Descriptor candidate) { calls++; return candidate is descriptor; };
    assert(ClassFilters.union_(ClassFilter.TRUE, failIfCalled).matches(descriptor));
    assert(!ClassFilters.intersection(ClassFilters.negate(ClassFilter.TRUE), failIfCalled).matches(descriptor));
    assert(calls == 0);
}
