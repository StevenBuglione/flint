/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/NameMatchMethodPointcutTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module name_match_pointcut_tests;

import flint.aop : ClassFilter;
import flint.aop.support : NameMatchMethodPointcut, Pointcuts;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;
import flint.java.lang : NullPointerException;
import std.exception : assertThrown;

@safe:

private final class TestPointcut : NameMatchMethodPointcut
{
    bool patternMatches(string name, string pattern)
    {
        return isMatch(name, pattern);
    }
}

@("NameMatchMethodPointcutTests.isMatch") unittest
{
    auto pointcut = new TestPointcut;
    assert(pointcut.patternMatches("echo", "echo"));
    assert(pointcut.patternMatches("echo", "ech*"));
    assert(pointcut.patternMatches("setName", "setN*"));
    assert(pointcut.patternMatches("setName", "set*"));
    assert(!pointcut.patternMatches("getName", "set*"));
    assert(!pointcut.patternMatches("setName", "set"));
    assert(pointcut.patternMatches("testing", "*ing"));
}

@("NameMatchMethodPointcutTests.equalsAndHashCode") unittest
{
    auto first = new NameMatchMethodPointcut;
    auto second = new NameMatchMethodPointcut;
    assert(first.equals(second));
    assert(first.hashCode() == second.hashCode());
    first.setMappedName("foo");
    assert(!first.equals(second));
    assert(first.hashCode() != second.hashCode());
    second.setMappedName("foo");
    assert(first.equals(second));
    assert(first.hashCode() == second.hashCode());
    second.addMethodName("bar");
    assert(!first.equals(second));
}

@("Name pointcuts replace pattern lists and select all overloads of the same name") unittest
{
    import flint.engine.aot.descriptor : ParameterDescriptor;

    auto pointcut = new NameMatchMethodPointcut;
    auto person = new Descriptor("fixtures.Person", TypeKind.class_);
    auto setName = new MethodDescriptor("setName", "void");
    setName.parameters = [ParameterDescriptor("name", "string")];
    auto setNameOverload = new MethodDescriptor("setName", "void");
    setNameOverload.parameters = [
        ParameterDescriptor("name", "string"), ParameterDescriptor("index", "int")
    ];
    auto echo = new MethodDescriptor("echo", "string");

    assert(pointcut.getClassFilter() is ClassFilter.TRUE);
    assert(!Pointcuts.matches(pointcut, echo, person));
    pointcut.addMethodName("echo").addMethodName("set*");
    assert(Pointcuts.matches(pointcut, echo, person));
    assert(Pointcuts.matches(pointcut, setName, person));
    assert(Pointcuts.matches(pointcut, setNameOverload, person));

    string[] input = ["set*"];
    pointcut.setMappedNames(input);
    input[0] = "echo";
    assert(Pointcuts.matches(pointcut, setName, person));
    assert(!Pointcuts.matches(pointcut, echo, person));

    pointcut.setClassFilter((const Descriptor candidate) => candidate.name == "fixtures.Other");
    assert(!Pointcuts.matches(pointcut, setName, person));

    pointcut.setClassFilter(ClassFilter.NULL);
    assert(pointcut.getClassFilter() is null);
    assertThrown!NullPointerException(Pointcuts.matches(pointcut, setName, person));
}
