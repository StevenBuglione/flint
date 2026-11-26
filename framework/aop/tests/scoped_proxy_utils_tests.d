/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/scope/ScopedProxyUtilsTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module scoped_proxy_utils_tests;

import flint.aop.scope_ : ScopedProxyUtils;
import flint.java.lang : IllegalArgumentException;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

@("ScopedProxyUtilsTests.getTargetBeanNameAndIsScopedTarget") unittest
{
    enum original = "myBean";
    const target = ScopedProxyUtils.getTargetBeanName(original);
    assert(target == "scopedTarget.myBean");
    assert(ScopedProxyUtils.isScopedTarget(target));
    assert(!ScopedProxyUtils.isScopedTarget(original));
}

@("ScopedProxyUtilsTests.getOriginalBeanNameAndIsScopedTarget") unittest
{
    enum original = "myBean";
    const target = ScopedProxyUtils.getTargetBeanName(original);
    const parsedName = ScopedProxyUtils.getOriginalBeanName(Nullable!string(target));
    assert(parsedName != target && parsedName == original);
    assert(ScopedProxyUtils.isScopedTarget(target));
    assert(!ScopedProxyUtils.isScopedTarget(parsedName));
}

@("ScopedProxyUtilsTests.getOriginalBeanNameForNullTargetBean") unittest
{
    const failure = collectException!IllegalArgumentException(
            ScopedProxyUtils.getOriginalBeanName(Nullable!string.init));
    assert(failure !is null);
    assert(failure.getMessage() == "bean name 'null' does not refer to the target of a scoped proxy");
    assert(!ScopedProxyUtils.isScopedTarget(null));
}

@("ScopedProxyUtilsTests.getOriginalBeanNameForNonScopedTarget") unittest
{
    const failure = collectException!IllegalArgumentException(
            ScopedProxyUtils.getOriginalBeanName(Nullable!string("myBean")));
    assert(failure !is null);
    assert(failure.getMessage() == "bean name 'myBean' does not refer to the target of a scoped proxy");
}

@("Scoped proxy names preserve empty and non-ASCII bean names") unittest
{
    const failure = collectException!IllegalArgumentException(
            ScopedProxyUtils.getOriginalBeanName(Nullable!string("")));
    assert(failure !is null);
    assert(failure.getMessage() == "bean name '' does not refer to the target of a scoped proxy");
    assert(!ScopedProxyUtils.isScopedTarget(""));

    foreach (original; ["", "météo", "scopedTarget.inner"])
    {
        const target = ScopedProxyUtils.getTargetBeanName(original);
        assert(ScopedProxyUtils.getOriginalBeanName(Nullable!string(target)) == original);
    }
}
