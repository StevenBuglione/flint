/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: EPL-2.0
 */
module aspectj_annotation_tests;

import flint.aspectj.lang.annotation : AdviceName, After, AfterReturning, AfterThrowing, Around, Aspect, Before,
    DeclareAnnotation, DeclareError, DeclareMixin, DeclareParents, DeclarePrecedence,
    DeclareWarning, Pointcut, RequiredTypes, SuppressAjWarnings;
import flint.java.classref : ClassRef, classOf;
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

@DeclareAnnotation("fixtures.Owner")
@RequiredTypes(["fixtures.Owner", "fixtures.Repository"])
@SuppressAjWarnings()
private final class DeclarationAspect
{
    @DeclareError("forbiddenCall()")
    static immutable string errorText = "forbidden";

    @DeclareWarning("deprecatedCall()")
    static immutable string warningText = "deprecated";

    @DeclareMixin("fixtures.Owner", [classOf!Auditable])
    static Auditable explicitMixin()
    {
        return new AuditMixin;
    }

    @DeclareMixin("fixtures.Owner")
    static Auditable inferredMixin()
    {
        return new AuditMixin;
    }

    @DeclareMixin("fixtures.Owner", [])
    @SuppressAjWarnings(["adviceDidNotMatch", "uncheckedArgument"])
    static Auditable emptyMixin()
    {
        return new AuditMixin;
    }
}

@("AspectJ declarations retain their selectors, dependency order and warning defaults") unittest
{
    enum declaration = getUDAs!(DeclarationAspect, DeclareAnnotation)[0];
    enum required = getUDAs!(DeclarationAspect, RequiredTypes)[0];
    enum defaults = getUDAs!(DeclarationAspect, SuppressAjWarnings)[0];
    enum configured = getUDAs!(DeclarationAspect.emptyMixin, SuppressAjWarnings)[0];
    enum error = getUDAs!(DeclarationAspect.errorText, DeclareError)[0];
    enum warning = getUDAs!(DeclarationAspect.warningText, DeclareWarning)[0];

    static assert(declaration.value == "fixtures.Owner");
    static assert(required.value == ["fixtures.Owner", "fixtures.Repository"]);
    static assert(defaults.value == [""]);
    static assert(configured.value == ["adviceDidNotMatch", "uncheckedArgument"]);
    static assert(error.value == "forbiddenCall()" && warning.value == "deprecatedCall()");
}

@("AspectJ mixin declarations distinguish supplied, inferred and empty interfaces") unittest
{
    enum explicit = getUDAs!(DeclarationAspect.explicitMixin, DeclareMixin)[0];
    enum inferred = getUDAs!(DeclarationAspect.inferredMixin, DeclareMixin)[0];
    enum empty = getUDAs!(DeclarationAspect.emptyMixin, DeclareMixin)[0];

    static assert(explicit.value == "fixtures.Owner" && explicit.interfaces == [classOf!Auditable]);
    static assert(inferred.interfaces == [ClassRef.init]);
    static assert(empty.interfaces.length == 0);
}
