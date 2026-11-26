/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/aspectj/autoproxy/AspectJPrecedenceComparatorTests.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.aspectj.autoproxy.precedence_comparator_tests;

import flint.aop : Advisor, AfterAdvice, BeforeAdvice;
import flint.aop.aspectj : AspectJAopUtils, AspectJPrecedenceInformation;
import flint.aop.aspectj.autoproxy : AspectJPrecedenceComparator;
import flint.aop.support : DefaultPointcutAdvisor;
import flint.aopalliance.aop : Advice;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;

@safe:

private enum high = 100;
private enum low = 200;
private enum early = 5;
private enum late = 10;
private enum aspect = "someAspect";
private enum otherAspect = "someOtherAspect";

private enum AdviceKind
{
    before,
    around,
    after
}

private final class AspectAdvice : Advice, AspectJPrecedenceInformation
{
    private AdviceKind kind;
    private int order;
    private int declarationOrder;
    private string aspectName;

    this(AdviceKind kind, int order, int declarationOrder, string aspectName)
    {
        this.kind = kind;
        this.order = order;
        this.declarationOrder = declarationOrder;
        this.aspectName = aspectName;
    }

    int getOrder()
    {
        return order;
    }

    int getDeclarationOrder()
    {
        return declarationOrder;
    }

    string getAspectName()
    {
        return aspectName;
    }

    bool isBeforeAdvice()
    {
        return kind == AdviceKind.before;
    }

    bool isAfterAdvice()
    {
        return kind == AdviceKind.after;
    }
}

private final class PlainBefore : BeforeAdvice
{
}

private final class PlainAfter : AfterAdvice
{
}

private final class LazyAdvisor : Advisor, AspectJPrecedenceInformation
{
    mixin Advisor.Defaults;
    Advice getAdvice()
    {
        assert(false, "Precedence lookup must leave lazy advice uninitialized");
    }

    int getOrder()
    {
        return high;
    }

    int getDeclarationOrder()
    {
        return early;
    }

    string getAspectName()
    {
        return aspect;
    }

    bool isBeforeAdvice()
    {
        return true;
    }

    bool isAfterAdvice()
    {
        return false;
    }
}

private Advisor advise(Advice advice, int order)
{
    auto advisor = new DefaultPointcutAdvisor(advice);
    advisor.setOrder(order);
    return advisor;
}

private Advisor before(int order, int declarationOrder, string aspectName)
{
    return advise(new AspectAdvice(AdviceKind.before, order, declarationOrder, aspectName), order);
}

private Advisor around(int order, int declarationOrder, string aspectName)
{
    return advise(new AspectAdvice(AdviceKind.around, order, declarationOrder, aspectName), order);
}

private Advisor after(int order, int declarationOrder, string aspectName)
{
    return advise(new AspectAdvice(AdviceKind.after, order, declarationOrder, aspectName), order);
}

@("sameAspectNoAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(before(high, early, aspect), before(high, late, aspect)) == -1);
    assert(comparator.compare(before(high, late, aspect), around(high, early, aspect)) == 1);
}

@("sameAspectAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(after(high, early, aspect), around(high, late, aspect)) == 1);
    assert(comparator.compare(after(high, late, aspect), after(high, early, aspect)) == -1);
}

@("sameAspectOneOfEach") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(after(high, early, aspect), before(high, late, aspect)) == 1);
}

@("sameAdvisorPrecedenceDifferentAspectNoAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(before(high, early, aspect), before(high, late, otherAspect)) == 0);
    assert(comparator.compare(before(high, late, aspect), around(high, early, otherAspect)) == 0);
}

@("sameAdvisorPrecedenceDifferentAspectAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(after(high, early, aspect), around(high, late, otherAspect)) == 0);
    assert(comparator.compare(after(high, late, aspect), after(high, early, otherAspect)) == 0);
}

@("higherAdvisorPrecedenceNoAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(advise(new PlainBefore, high), before(low, early, otherAspect)) == -1);
    assert(comparator.compare(before(high, late, aspect), around(low, early, otherAspect)) == -1);
}

@("higherAdvisorPrecedenceAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(after(high, early, aspect), around(low, late, otherAspect)) == -1);
    assert(comparator.compare(after(high, late, aspect), after(low, early, otherAspect)) == -1);
}

@("lowerAdvisorPrecedenceNoAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(before(low, early, aspect), before(high, early, otherAspect)) == 1);
    assert(comparator.compare(before(low, late, aspect), around(high, early, otherAspect)) == 1);
}

@("lowerAdvisorPrecedenceAfterAdvice") unittest
{
    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(after(low, early, aspect), around(high, late, otherAspect)) == 1);
    assert(comparator.compare(advise(new PlainAfter, low), after(high, early, otherAspect)) == 1);
}

@("Advisor precedence is available without initializing lazy advice") unittest
{
    auto advisor = new LazyAdvisor;
    assert(AspectJAopUtils.getAspectJPrecedenceInformationFor(advisor) is advisor);
    assert(AspectJAopUtils.isBeforeAdvice(advisor));
    assert(!AspectJAopUtils.isAfterAdvice(advisor));

    auto comparator = new AspectJPrecedenceComparator;
    assert(comparator.compare(advisor, before(high, late, aspect)) == -1);
    assert(comparator.compare(advisor, before(high, early, aspect)) == 0);
}

@("Advisor precedence falls back to the advice metadata and marker interfaces") unittest
{
    auto advice = new AspectAdvice(AdviceKind.after, high, early, aspect);
    auto advisor = advise(advice, high);
    assert(AspectJAopUtils.getAspectJPrecedenceInformationFor(advisor) is advice);
    assert(AspectJAopUtils.isAfterAdvice(advisor));
    assert(!AspectJAopUtils.isBeforeAdvice(advisor));

    Advisor plainAfter = advise(new PlainAfter, high);
    Advisor plainBefore = advise(new PlainBefore, high);
    assert(AspectJAopUtils.getAspectJPrecedenceInformationFor(plainAfter) is null);
    assert(AspectJAopUtils.isAfterAdvice(plainAfter));
    assert(!AspectJAopUtils.isBeforeAdvice(plainAfter));
    assert(AspectJAopUtils.isBeforeAdvice(plainBefore));
    assert(!AspectJAopUtils.isAfterAdvice(plainBefore));
}

@("The supplied advisor comparator takes priority over declaration order") unittest
{
    auto earlier = before(high, early, aspect);
    auto later = after(high, late, aspect);
    auto comparator = new AspectJPrecedenceComparator((Advisor first, Advisor second) {
        assert(first is earlier && second is later);
        return 7;
    });
    assert(comparator.compare(earlier, later) == 7);
    assertThrown!IllegalArgumentException(new AspectJPrecedenceComparator(null));
}
