/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/AspectJPrecedenceInformation.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/aspectj/AspectJAopUtils.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.aspectj;

import flint.aop : Advisor, AfterAdvice, BeforeAdvice;
import flint.core : Ordered;

@safe:

/// Supplies the metadata for comparing advice and advisors by AspectJ precedence.
interface AspectJPrecedenceInformation : Ordered
{
    /// Returns the name of the aspect declaring the advice.
    string getAspectName();

    /// Returns the advice member's declaration order within the aspect.
    int getDeclarationOrder();

    /// Whether the advice runs before the join point.
    bool isBeforeAdvice();

    /// Whether the advice is a form of after advice.
    bool isAfterAdvice();
}

/// Inspects AspectJ advisors and the advice they carry.
abstract class AspectJAopUtils
{
    /// Whether this advisor provides a form of before advice.
    static bool isBeforeAdvice(Advisor advisor)
    {
        if (auto precedence = getAspectJPrecedenceInformationFor(advisor))
            return precedence.isBeforeAdvice();
        return cast(BeforeAdvice) advisor.getAdvice() !is null;
    }

    /// Whether this advisor provides a form of after advice.
    static bool isAfterAdvice(Advisor advisor)
    {
        if (auto precedence = getAspectJPrecedenceInformationFor(advisor))
            return precedence.isAfterAdvice();
        return cast(AfterAdvice) advisor.getAdvice() !is null;
    }

    /// Reads advisor metadata without instantiating advice when the advisor supplies it.
    static AspectJPrecedenceInformation getAspectJPrecedenceInformationFor(Advisor advisor)
    {
        if (auto precedence = cast(AspectJPrecedenceInformation) advisor)
            return precedence;
        return cast(AspectJPrecedenceInformation) advisor.getAdvice();
    }
}
