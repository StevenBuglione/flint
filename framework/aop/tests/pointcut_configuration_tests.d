module pointcut_configuration_tests;

import flint.aop : Advisor, ClassFilter, MethodMatcher, Pointcut;
import flint.aop.support : AbstractExpressionPointcut, ExpressionPointcut, NameMatchMethodPointcutAdvisor, Pointcuts;
import flint.aopalliance.aop : Advice;
import flint.core : Ordered;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;
import flint.java.lang : IllegalArgumentException;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private final class OrderedAdvice : Advice, Ordered
{
    int getOrder()
    {
        return 7;
    }
}

@("Name-match advisors configure the pointcut returned by getPointcut") unittest
{
    auto advisor = new NameMatchMethodPointcutAdvisor;
    auto pointcut = advisor.getPointcut();
    auto target = new Descriptor("fixtures.Service", TypeKind.class_);
    auto other = new Descriptor("fixtures.OtherService", TypeKind.class_);
    auto read = new MethodDescriptor("read", "string");
    auto save = new MethodDescriptor("saveRecord", "void");
    assert(advisor.getAdvice() is Advisor.EMPTY_ADVICE);
    assert(!Pointcuts.matches(pointcut, read, target));

    advisor.setMappedName("read");
    assert(Pointcuts.matches(pointcut, read, target));
    advisor.setMappedNames("save*", "delete");
    assert(!Pointcuts.matches(pointcut, read, target));
    assert(Pointcuts.matches(pointcut, save, target));

    assert(cast(Pointcut) advisor.addMethodName("read") is pointcut);
    assert(Pointcuts.matches(pointcut, read, target));

    advisor.setClassFilter((const Descriptor candidate) => candidate.name == target.name);
    assert(Pointcuts.matches(pointcut, save, target));
    assert(!Pointcuts.matches(pointcut, save, other));
    advisor.setClassFilter(ClassFilter.TRUE);
    assert(Pointcuts.matches(pointcut, save, other));
}

@("Name-match advisors use the configured advice's order unless explicitly overridden") unittest
{
    auto advice = new OrderedAdvice;
    auto advisor = new NameMatchMethodPointcutAdvisor(advice);
    auto other = new NameMatchMethodPointcutAdvisor(advice);
    assert(advisor.getAdvice() is advice);
    assert(advisor.getOrder() == 7);
    advisor.setOrder(2);
    assert(advisor.getOrder() == 2);

    advisor.setMappedName("read");
    assert(!advisor.equals(other));
    other.setMappedName("read");
    assert(advisor.equals(other));
}

private class TestExpression : AbstractExpressionPointcut
{
    ClassFilter getClassFilter()
    {
        return ClassFilter.TRUE;
    }

    MethodMatcher getMethodMatcher()
    {
        return MethodMatcher.TRUE;
    }
}

private final class ValidatingExpression : TestExpression
{
    IllegalArgumentException failure = new IllegalArgumentException("bad selector");

    protected override void onSetExpression(Nullable!string expression)
    {
        assert(getExpression() == expression);
        throw failure;
    }
}

@("Expression pointcuts distinguish absent and empty configuration") unittest
{
    auto pointcut = new TestExpression;
    ExpressionPointcut expression = pointcut;
    assert(expression.getExpression().isNull);
    assert(pointcut.getLocation().isNull);

    pointcut.setExpression(Nullable!string(""));
    pointcut.setLocation(Nullable!string(""));
    assert(!expression.getExpression().isNull && expression.getExpression().get.length == 0);
    assert(!pointcut.getLocation().isNull && pointcut.getLocation().get.length == 0);

    pointcut.setExpression(Nullable!string.init);
    pointcut.setLocation(Nullable!string.init);
    assert(expression.getExpression().isNull && pointcut.getLocation().isNull);
}

@("Expression pointcuts preserve failures without location and wrap them with configured location") unittest
{
    auto pointcut = new ValidatingExpression;
    auto expression = Nullable!string("invalid");
    auto original = collectException!IllegalArgumentException(pointcut.setExpression(expression));
    assert(original is pointcut.failure);
    assert(pointcut.getExpression() == expression);

    pointcut.setLocation(Nullable!string(""));
    auto located = collectException!IllegalArgumentException(pointcut.setExpression(expression));
    assert(located !is null && located !is original);
    assert(located.getCause() is null);
    assert(located.getMessage() == "Invalid expression at location []: " ~ original.toString());
}
