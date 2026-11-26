/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/autoproxy/AspectJPrecedenceComparator.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.aspectj.autoproxy;

import flint.aop : Advisor;
import flint.aop.aspectj : AspectJAopUtils;
import flint.core.annotation.types : AnnotationAwareOrderComparator;
import flint.java.lang : IllegalArgumentException;

@safe:

/// Compares precedence within an aspect after the regular advisor order.
package(flint.aop.aspectj) final class AspectJPrecedenceComparator
{
    private int delegate(Advisor, Advisor) @safe advisorComparator;

    this()
    {
        auto order = AnnotationAwareOrderComparator.INSTANCE;
        this((Advisor first, Advisor second) => order.compare(cast(Object) first, cast(Object) second));
    }

    this(int delegate(Advisor, Advisor) @safe advisorComparator)
    {
        if (advisorComparator is null)
            throw new IllegalArgumentException("Advisor comparator must not be null");
        this.advisorComparator = advisorComparator;
    }

    /// A zero result leaves the two advisors unordered with respect to this comparison.
    int compare(Advisor first, Advisor second)
    {
        const advisorOrder = advisorComparator(first, second);
        if (advisorOrder != 0)
            return advisorOrder;

        auto firstInfo = AspectJAopUtils.getAspectJPrecedenceInformationFor(first);
        if (firstInfo is null)
            return 0;
        auto secondInfo = AspectJAopUtils.getAspectJPrecedenceInformationFor(second);
        if (secondInfo is null || firstInfo.getAspectName() != secondInfo.getAspectName())
            return 0;

        const afterAdvice = firstInfo.isAfterAdvice() || secondInfo.isAfterAdvice();
        const declarationDelta = firstInfo.getDeclarationOrder() - secondInfo.getDeclarationOrder();
        if (declarationDelta == 0)
            return 0;
        return (declarationDelta < 0) == afterAdvice ? 1 : -1;
    }
}
