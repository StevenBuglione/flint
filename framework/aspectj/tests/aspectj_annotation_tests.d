/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: EPL-2.0
 */
module aspectj_annotation_tests;

import flint.aspectj.lang.annotation : AdviceName, After, AfterReturning, AfterThrowing, Around,
    Aspect, Before, DeclareParents, DeclarePrecedence, Pointcut;
import flint.java.classref : classOf;
import std.traits : getUDAs;

@safe:

private interface Auditable
{
}

private final class AuditMixin : Auditable
{
}

@Aspect("pertarget(ownerWrite())")
@DeclarePrecedence("AuditAspect, *")
private final class AuditAspect
{
    @Pointcut("execution(* *.rename(..))", "name")
    void ownerWrite(string name)
    {
        assert(name.length != 0);
    }

    @AdviceName("audit")
    @Before("ownerWrite(name)", "name")
    void record(string name)
    {
        assert(name.length != 0);
    }

    @Around("ownerWrite(name)", "name")
    void around(string name)
    {
        assert(name.length != 0);
    }

    @After("ownerWrite(name)")
    void close(string name)
    {
        assert(name.length != 0);
    }

    @AfterReturning("", "ownerWrite(name)", "result", "name,result")
    void completed(string name, string result)
    {
        assert(name.length != 0 && result.length != 0);
    }

    @AfterThrowing("ownerWrite(name)", "", "failure", "name,failure")
    void failed(string name, Exception failure)
    {
        assert(name.length != 0 && failure !is null);
    }

    @DeclareParents("fixtures.Owner+", classOf!AuditMixin)
    Auditable introduced;
}

@("AspectJ advice metadata retains named bindings and defaults") unittest
{
    enum aspect = getUDAs!(AuditAspect, Aspect)[0];
    enum pointcut = getUDAs!(AuditAspect.ownerWrite, Pointcut)[0];
    enum adviceName = getUDAs!(AuditAspect.record, AdviceName)[0];
    enum before = getUDAs!(AuditAspect.record, Before)[0];
    enum around = getUDAs!(AuditAspect.around, Around)[0];
    enum after = getUDAs!(AuditAspect.close, After)[0];
    enum returning = getUDAs!(AuditAspect.completed, AfterReturning)[0];
    enum throwing = getUDAs!(AuditAspect.failed, AfterThrowing)[0];

    static assert(Aspect.init.value == "");
    static assert(Pointcut.init.value == "" && Pointcut.init.argNames == "");
    static assert(aspect.value == "pertarget(ownerWrite())");
    static assert(pointcut.value == "execution(* *.rename(..))" && pointcut.argNames == "name");
    static assert(adviceName.value == "audit");
    static assert(before.value == "ownerWrite(name)" && before.argNames == "name");
    static assert(around.value == before.value && around.argNames == before.argNames);
    static assert(after.value == before.value && after.argNames == "");
    static assert(returning.value == "" && returning.pointcut == before.value);
    static assert(returning.returning == "result" && returning.argNames == "name,result");
    static assert(throwing.value == before.value && throwing.pointcut == "");
    static assert(throwing.throwing == "failure" && throwing.argNames == "name,failure");
}

@("AspectJ introduction and precedence metadata preserve class tokens and order") unittest
{
    enum parents = getUDAs!(AuditAspect.introduced, DeclareParents)[0];
    enum precedence = getUDAs!(AuditAspect, DeclarePrecedence)[0];
    static assert(parents.value == "fixtures.Owner+" && parents.defaultImpl == classOf!AuditMixin);
    static assert(DeclareParents.init.defaultImpl == classOf!DeclareParents);
    static assert(precedence.value == "AuditAspect, *");
}
