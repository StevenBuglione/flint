module proxy_contract_tests;

import flint.aop : Advisor, ProxyMethodInvocation, TargetSource;
import flint.aop.framework : Advised, ProxyConfig;
import flint.aop.support : DefaultPointcutAdvisor;
import flint.aopalliance.aop : Advice;
import flint.aopalliance.intercept : MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor;

@safe:

static assert(is(ProxyMethodInvocation : MethodInvocation));
static assert(is(typeof(ProxyMethodInvocation.init.getProxy()) == Any));
static assert(is(typeof(ProxyMethodInvocation.init.invocableClone()) == MethodInvocation));
static assert(is(typeof(ProxyMethodInvocation.init.invocableClone(Any.of(7))) == MethodInvocation));
static assert(is(typeof(ProxyMethodInvocation.init.setArguments(Any.of(7), Any.init)) == void));
static assert(is(typeof(ProxyMethodInvocation.init.setUserAttribute("key", Any.init)) == void));
static assert(is(typeof(ProxyMethodInvocation.init.getUserAttribute("key")) == Any));

private class AdvisedFixture : ProxyConfig, Advised
{
    mixin Advised.Defaults;

    override bool isFrozen()
    {
        return super.isFrozen();
    }

    override bool isProxyTargetClass()
    {
        return super.isProxyTargetClass();
    }

    override void setExposeProxy(bool exposeProxy)
    {
        super.setExposeProxy(exposeProxy);
    }

    override bool isExposeProxy()
    {
        return super.isExposeProxy();
    }

    Advisor[] getAdvisors()
    {
        assert(0, "the default count must use the override");
    }

    const(Descriptor) getTargetClass()
    {
        assert(0);
    }

    const(Descriptor)[] getProxiedInterfaces()
    {
        assert(0);
    }

    bool isInterfaceProxied(const Descriptor)
    {
        assert(0);
    }

    void setTargetSource(TargetSource)
    {
        assert(0);
    }

    TargetSource getTargetSource()
    {
        assert(0);
    }

    void setPreFiltered(bool)
    {
        assert(0);
    }

    bool isPreFiltered()
    {
        assert(0);
    }

    void addAdvisor(Advisor)
    {
        assert(0);
    }

    void addAdvisor(int, Advisor)
    {
        assert(0);
    }

    bool removeAdvisor(Advisor)
    {
        assert(0);
    }

    void removeAdvisor(int)
    {
        assert(0);
    }

    int indexOf(Advisor)
    {
        assert(0);
    }

    bool replaceAdvisor(Advisor, Advisor)
    {
        assert(0);
    }

    void addAdvice(Advice)
    {
        assert(0);
    }

    void addAdvice(int, Advice)
    {
        assert(0);
    }

    bool removeAdvice(Advice)
    {
        assert(0);
    }

    int indexOf(Advice)
    {
        assert(0);
    }

    string toProxyConfigString()
    {
        assert(0);
    }
}

private final class ConfiguredAdvisors : AdvisedFixture
{
    Advisor[] advisors;
    int reads;

    override Advisor[] getAdvisors()
    {
        ++reads;
        return advisors;
    }
}

@("Advised's default count uses the current advisor list through virtual dispatch") unittest
{
    auto configured = new ConfiguredAdvisors;
    Advised proxy = configured;
    assert(proxy.getAdvisorCount() == 0);
    assert(configured.reads == 1);

    configured.advisors = [new DefaultPointcutAdvisor, new DefaultPointcutAdvisor];
    assert(proxy.getAdvisorCount() == 2);
    assert(configured.reads == 2);

    proxy.setExposeProxy(true);
    assert(configured.isExposeProxy());
}
