module expose_bean_name_tests;

import flint.aop : Pointcut, PointcutAdvisor, ProxyMethodInvocation;
import flint.aop.interceptor : ExposeBeanNameAdvisors;
import flint.aopalliance.intercept : MethodInterceptor, MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : MemberDescriptorRef, MethodDescriptor;
import flint.java.lang : ClassCastException, IllegalArgumentException, IllegalStateException;
import std.exception : assertThrown, collectException;

@safe:

private final class ProxyCall : ProxyMethodInvocation
{
    private Any attribute;
    string attributeName;
    string nameAtProceed;
    Any result;
    Exception failure;

    Any proceed()
    {
        nameAtProceed = ExposeBeanNameAdvisors.getBeanName(this);
        if (failure !is null)
            throw failure;
        return result;
    }

    void setUserAttribute(string key, Any value)
    {
        attributeName = key;
        attribute = value;
    }

    Any getUserAttribute(string key)
    {
        return key == attributeName ? attribute : Any.init;
    }

    Any getThis()
    {
        return Any.init;
    }

    Any getProxy()
    {
        return Any.init;
    }

    MemberDescriptorRef getStaticPart()
    {
        return MemberDescriptorRef.init;
    }

    const(MethodDescriptor)* getMethod()
    {
        return null;
    }

    Any[] getArguments()
    {
        return null;
    }

    MethodInvocation invocableClone()
    {
        assert(0);
    }

    MethodInvocation invocableClone(Any[]...)
    {
        assert(0);
    }

    void setArguments(Any[]...)
    {
        assert(0);
    }
}

@("Bean name advice exposes the name during proceed and preserves the result") unittest
{
    auto advisor = cast(PointcutAdvisor) ExposeBeanNameAdvisors.createAdvisorWithoutIntroduction("service");
    assert(advisor !is null && advisor.getPointcut() is Pointcut.TRUE);

    auto interceptor = cast(MethodInterceptor) advisor.getAdvice();
    auto call = new ProxyCall;
    auto result = new Object;
    call.result = Any.of(result);

    assert(interceptor.invoke(call).asObject() is result);
    assert(call.nameAtProceed == "service");
    assert(ExposeBeanNameAdvisors.getBeanName(call) == "service");
}

@("Bean name advice preserves an empty name and propagates a target exception") unittest
{
    auto advisor = ExposeBeanNameAdvisors.createAdvisorWithoutIntroduction("");
    auto interceptor = cast(MethodInterceptor) advisor.getAdvice();
    auto call = new ProxyCall;
    call.failure = new Exception("target failure");

    assert(collectException(interceptor.invoke(call)) is call.failure);
    assert(call.nameAtProceed == "");
    assert(ExposeBeanNameAdvisors.getBeanName(call) == "");
}

@("Bean name exposure rejects non-proxy calls and invalid attributes") unittest
{
    assertThrown!IllegalArgumentException(ExposeBeanNameAdvisors.getBeanName(null));

    auto call = new ProxyCall;
    assertThrown!IllegalStateException(ExposeBeanNameAdvisors.getBeanName(call));

    auto advisor = ExposeBeanNameAdvisors.createAdvisorWithoutIntroduction("service");
    auto interceptor = cast(MethodInterceptor) advisor.getAdvice();
    assertThrown!IllegalStateException(interceptor.invoke(null));

    interceptor.invoke(call);
    call.setUserAttribute(call.attributeName, Any.of(42));
    assertThrown!ClassCastException(ExposeBeanNameAdvisors.getBeanName(call));
}
