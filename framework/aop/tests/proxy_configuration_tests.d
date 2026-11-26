module proxy_configuration_tests;

import std.exception : assertThrown;

import flint.aop : Advisor, Pointcut, PointcutAdvisor, TargetClassAware, TargetSource;
import flint.aop.framework.autoproxy : TargetSourceCreator;
import flint.aop.support : AbstractGenericPointcutAdvisor, DefaultPointcutAdvisor,
    NameMatchMethodPointcut, Pointcuts, StaticMethodMatcherPointcutAdvisor;
import flint.aopalliance.aop : Advice;
import flint.core : Ordered;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;
import flint.java.lang : IllegalArgumentException;

@safe:

private final class OrderedAdvice : Advice, Ordered
{
    private int order;

    this(int order)
    {
        this.order = order;
    }

    int getOrder()
    {
        return order;
    }

    override string toString() const
    {
        return "ordered advice";
    }
}

private final class GenericAdvisor : AbstractGenericPointcutAdvisor
{
    bool failOnAdviceRead;

    override Pointcut getPointcut()
    {
        return Pointcuts.GETTERS;
    }

    override Advice getAdvice()
    {
        if (failOnAdviceRead)
            throw new IllegalArgumentException("an explicit order must bypass the advice");
        return super.getAdvice();
    }
}

private final class ReadAdvisor : StaticMethodMatcherPointcutAdvisor
{
    this()
    {
    }

    this(Advice advice)
    {
        super(advice);
    }

    override bool matches(const(MethodDescriptor)* method, const Descriptor targetClass)
    {
        return method.name == "read";
    }
}

private final class ConfiguredTarget : TargetSource
{
    mixin TargetSource.Defaults;

    private Descriptor descriptor;
    private Any target;

    this(Descriptor descriptor, Any target)
    {
        this.descriptor = descriptor;
        this.target = target;
    }

    const(Descriptor) getTargetClass()
    {
        return descriptor;
    }

    Any getTarget()
    {
        return target;
    }
}

private final class NamedTargetSourceCreator : TargetSourceCreator
{
    private TargetSource target;

    this(TargetSource target)
    {
        this.target = target;
    }

    TargetSource getTargetSource(const Descriptor beanClass, string beanName)
    {
        return beanClass is target.getTargetClass() && beanName == "pooledService" ? target : null;
    }
}

@("Target source creators select by bean type and name and can decline a bean") unittest
{
    auto service = new Descriptor("example.Service", TypeKind.class_);
    auto other = new Descriptor("example.Other", TypeKind.class_);
    auto target = new ConfiguredTarget(service, Any.init);
    TargetSourceCreator creator = new NamedTargetSourceCreator(target);

    assert(creator.getTargetSource(service, "pooledService") is target);
    assert(creator.getTargetSource(service, "plainService") is null);
    assert(creator.getTargetSource(other, "pooledService") is null);
}

@("Pointcut and advice defaults survive bean-style configuration") unittest
{
    auto advisor = new DefaultPointcutAdvisor;
    assert(advisor.getAdvice() is Advisor.EMPTY_ADVICE);
    assert(advisor.getPointcut() is Pointcut.TRUE);
    assert(advisor.isPerInstance());
    assert(advisor.getOrder() == Ordered.LOWEST_PRECEDENCE);

    auto advice = new OrderedAdvice(5);
    auto configured = new DefaultPointcutAdvisor(advice);
    assert(configured.getAdvice() is advice);
    assert(configured.getPointcut() is Pointcut.TRUE);
    assert(configured.getOrder() == 5);
    enum advisorName = "flint.aop.support.DefaultPointcutAdvisor";
    assert(configured.toString() == advisorName ~ ": pointcut [Pointcut.TRUE]; advice [ordered advice]");

    auto pointcut = new NameMatchMethodPointcut().addMethodName("read");
    advisor.setPointcut(pointcut);
    advisor.setAdvice(advice);
    assert(advisor.getPointcut() is pointcut);
    assert(advisor.getAdvice() is advice);
    advisor.setPointcut(null);
    assert(advisor.getPointcut() is Pointcut.TRUE);
    assert((new DefaultPointcutAdvisor(null, advice)).getPointcut() is null);
}

@("An explicit order outranks Ordered advice even at LOWEST_PRECEDENCE") unittest
{
    auto advisor = new GenericAdvisor;
    assert(advisor.getOrder() == Ordered.LOWEST_PRECEDENCE);
    assert(advisor.getAdvice() is Advisor.EMPTY_ADVICE);
    advisor.setAdvice(new OrderedAdvice(4));
    assert(advisor.getOrder() == 4);
    assert(advisor.toString() == typeid(GenericAdvisor).name ~ ": advice [ordered advice]");

    advisor.setAdvice(new OrderedAdvice(8));
    assert(advisor.getOrder() == 8);
    advisor.setOrder(Ordered.LOWEST_PRECEDENCE);
    advisor.failOnAdviceRead = true;
    assert(advisor.getOrder() == Ordered.LOWEST_PRECEDENCE);
    advisor.failOnAdviceRead = false;
    advisor.setOrder(Ordered.HIGHEST_PRECEDENCE);
    advisor.setAdvice(null);
    assert(advisor.getAdvice() is null);
    assert(advisor.getOrder() == Ordered.HIGHEST_PRECEDENCE);
}

@("Advisor equality compares the pointcut and advice independently of order") unittest
{
    auto advice = new OrderedAdvice(5);
    auto first = new DefaultPointcutAdvisor(new NameMatchMethodPointcut().addMethodName("read"), advice);
    auto equivalent = new DefaultPointcutAdvisor(new NameMatchMethodPointcut().addMethodName("read"), advice);
    auto differentPointcut = new DefaultPointcutAdvisor(new NameMatchMethodPointcut().addMethodName("write"), advice);
    auto differentAdvice = new DefaultPointcutAdvisor(first.getPointcut(), new OrderedAdvice(5));
    equivalent.setOrder(7);

    assert(first.equals(first));
    assert(first.equals(equivalent) && first == equivalent);
    assert(first.hashCode() == equivalent.hashCode());
    assert(!first.equals(differentPointcut));
    assert(!first.equals(differentAdvice));
    assert(!first.equals(null));
    assert(!first.equals(new Object));
    assert((new DefaultPointcutAdvisor(null, null)).equals(new DefaultPointcutAdvisor(null, null)));
}

@("A static pointcut advisor serves as its own pointcut and uses its own order") unittest
{
    auto read = new MethodDescriptor("read", "void");
    auto write = new MethodDescriptor("write", "void");
    auto target = new Descriptor("Target", TypeKind.class_);
    auto advice = new OrderedAdvice(12);
    auto empty = new ReadAdvisor;
    assert(empty.getAdvice() is Advisor.EMPTY_ADVICE);
    assertThrown!IllegalArgumentException(new ReadAdvisor(null));

    auto advisor = new ReadAdvisor(advice);
    PointcutAdvisor contract = advisor;
    assert(contract.getPointcut() is cast(Pointcut) advisor);
    assert(contract.getAdvice() is advice && contract.isPerInstance());
    assert(Pointcuts.matches(contract.getPointcut(), read, target));
    assert(!Pointcuts.matches(contract.getPointcut(), write, target));
    assert(advisor.getOrder() == Ordered.LOWEST_PRECEDENCE);
    advisor.setOrder(-4);
    assert(advisor.getOrder() == -4);
    advisor.setAdvice(null);
    assert(contract.getAdvice() is null);
}

@("A TargetSource exposes erased targets and defaults to dynamic with no release hook") unittest
{
    auto descriptor = new Descriptor("Target", TypeKind.class_);
    auto instance = new Object;
    TargetSource source = new ConfiguredTarget(descriptor, Any.of(instance));
    TargetClassAware classes = source;
    assert(classes.getTargetClass() is descriptor);
    assert(!source.isStatic());
    assert(source.getTarget().asObject() is instance);
    source.releaseTarget(source.getTarget());
    assert(source.getTarget().asObject() is instance);

    source = new ConfiguredTarget(null, Any.init);
    assert(source.getTargetClass() is null && source.getTarget().isNull());
    source.releaseTarget(Any.init);
}
