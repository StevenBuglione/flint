/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/ProxyConfig.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/AopConfigException.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/Advised.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/AdvisorChainFactory.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/AopInfrastructureBean.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/AopProxy.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.framework;

import flint.aop : Advisor, TargetClassAware, TargetSource;
import flint.aopalliance.aop : Advice;
import flint.core : NestedRuntimeException;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : List;

@safe:

/// Builds interception chains for the methods of an advised proxy.
interface AdvisorChainFactory
{
    /// Returns interceptors and dynamically matched chain entries in invocation order.
    /// A null targetClass uses the method's declaring type.
    List!Any getInterceptorsAndDynamicInterceptionAdvice(Advised config, MemberDescriptorRef method,
            const Descriptor targetClass);
}

/// Marks AOP infrastructure beans for exclusion from auto-proxying.
interface AopInfrastructureBean
{
}

/// Creates proxy instances from a configured, ahead-of-time generated proxy.
interface AopProxy
{
    /// Returns a new proxy instance (R23).
    Any getProxy();
}

/// Exposes a proxy's target source, proxied interfaces and advisor configuration.
interface Advised : TargetClassAware
{
    /// Whether changes to the advice configuration are prohibited.
    bool isFrozen();

    /// Whether the full target class is proxied.
    bool isProxyTargetClass();

    /// Returns the descriptors of the proxied interfaces.
    const(Descriptor)[] getProxiedInterfaces();

    /// Whether the given interface is proxied.
    bool isInterfaceProxied(const Descriptor interfaceType);

    /// Replaces the target source on an unfrozen proxy.
    void setTargetSource(TargetSource targetSource);

    /// Returns the target source.
    TargetSource getTargetSource();

    /// Configures whether the current proxy is exposed during an invocation.
    void setExposeProxy(bool exposeProxy);

    /// Whether to expose the proxy during an invocation.
    bool isExposeProxy();

    /// Records whether the advisors are already filtered for the target class.
    void setPreFiltered(bool preFiltered);

    /// Whether advisor class filters may be skipped when the chain is built.
    bool isPreFiltered();

    /// Returns the current advisors in chain order.
    Advisor[] getAdvisors();

    /// Returns the number of current advisors.
    int getAdvisorCount();

    /// Appends an advisor to the chain.
    void addAdvisor(Advisor advisor);

    /// Inserts an advisor at the zero-based position.
    void addAdvisor(int position, Advisor advisor);

    /// Removes a matching advisor and reports whether it was present.
    bool removeAdvisor(Advisor advisor);

    /// Removes the advisor at the given position.
    void removeAdvisor(int index);

    /// Returns the position of the advisor, or -1 if it is absent.
    int indexOf(Advisor advisor);

    /// Replaces the advisor and reports whether it was present.
    bool replaceAdvisor(Advisor original, Advisor replacement);

    /// Appends advice with a pointcut that applies to all invocations.
    void addAdvice(Advice advice);

    /// Inserts advice at the zero-based position.
    void addAdvice(int position, Advice advice);

    /// Removes the advisor that contains the advice.
    bool removeAdvice(Advice advice);

    /// Returns the position of the advice, or -1 if it is absent.
    int indexOf(Advice advice);

    /// Describes the proxy configuration directly.
    string toProxyConfigString();

    /// R3 implementation of the Java default method.
    mixin template Defaults()
    {
        /// Counts the advisors supplied by the implementation.
        int getAdvisorCount()
        {
            Advised proxy = this;
            return cast(int) proxy.getAdvisors().length;
        }
    }
}

private enum ProxyFlag : ubyte
{
    unset,
    disabled,
    enabled,
}

private struct ProxyFlags
{
    ProxyFlag proxyTargetClass;
    ProxyFlag optimize;
    ProxyFlag opaque;
    ProxyFlag exposeProxy;
    ProxyFlag frozen;
}

private ProxyFlag flagValue(bool enabled) pure nothrow @nogc
{
    return enabled ? ProxyFlag.enabled : ProxyFlag.disabled;
}

private ProxyFlag flagWithDefault(ProxyFlag current, ProxyFlag fallback) pure nothrow @nogc
{
    return current == ProxyFlag.unset ? fallback : current;
}

private string flagText(ProxyFlag flag) pure nothrow @nogc
{
    final switch (flag)
    {
    case ProxyFlag.unset:
        return "null";
    case ProxyFlag.disabled:
        return "false";
    case ProxyFlag.enabled:
        return "true";
    }
}

/// The common configuration of AOP proxy creators.
class ProxyConfig
{
    private ProxyFlags flags;

    /// Selects proxying of the target class as well as its interfaces.
    void setProxyTargetClass(bool proxyTargetClass)
    {
        flags.proxyTargetClass = flagValue(proxyTargetClass);
    }

    /// Whether to proxy the target class directly.
    bool isProxyTargetClass()
    {
        return flags.proxyTargetClass == ProxyFlag.enabled;
    }

    /// Configures aggressive proxy optimizations.
    void setOptimize(bool optimize)
    {
        flags.optimize = flagValue(optimize);
    }

    /// Whether optimizations were enabled.
    bool isOptimize()
    {
        return flags.optimize == ProxyFlag.enabled;
    }

    /// Configures whether clients can inspect the proxy through Advised.
    void setOpaque(bool opaque)
    {
        flags.opaque = flagValue(opaque);
    }

    /// Whether the proxy's advice configuration is opaque.
    bool isOpaque()
    {
        return flags.opaque == ProxyFlag.enabled;
    }

    /// Configures whether the proxy is exposed during an advised invocation.
    void setExposeProxy(bool exposeProxy)
    {
        flags.exposeProxy = flagValue(exposeProxy);
    }

    /// Whether an advised invocation exposes the current proxy.
    bool isExposeProxy()
    {
        return flags.exposeProxy == ProxyFlag.enabled;
    }

    /// Configures whether subsequent changes to the proxy's advice are allowed.
    void setFrozen(bool frozen)
    {
        flags.frozen = flagValue(frozen);
    }

    /// Whether the proxy's advice configuration is frozen.
    bool isFrozen()
    {
        return flags.frozen == ProxyFlag.enabled;
    }

    /// Replaces every flag with its value from the other configuration.
    void copyFrom(ProxyConfig other)
    {
        if (other is null)
            throw new IllegalArgumentException("Other ProxyConfig object must not be null");
        flags = other.flags;
    }

    /// Fills only flags that have no local setting.
    void copyDefault(ProxyConfig other)
    {
        if (other is null)
            throw new IllegalArgumentException("Other ProxyConfig object must not be null");
        const defaults = other.flags;
        flags.proxyTargetClass = flagWithDefault(flags.proxyTargetClass, defaults.proxyTargetClass);
        flags.optimize = flagWithDefault(flags.optimize, defaults.optimize);
        flags.opaque = flagWithDefault(flags.opaque, defaults.opaque);
        flags.exposeProxy = flagWithDefault(flags.exposeProxy, defaults.exposeProxy);
        flags.frozen = flagWithDefault(flags.frozen, defaults.frozen);
    }

    /// Describes all flags, including those that are unset.
    override string toString() const
    {
        return "proxyTargetClass=" ~ flagText(flags.proxyTargetClass) ~ "; optimize=" ~ flagText(
                flags.optimize) ~ "; opaque=" ~ flagText(flags.opaque) ~ "; exposeProxy=" ~ flagText(
                flags.exposeProxy) ~ "; frozen=" ~ flagText(flags.frozen);
    }
}

/// An illegal AOP configuration.
class AopConfigException : NestedRuntimeException
{
    /// Records the configuration failure.
    this(string message)
    {
        super(message);
    }

    /// Records the configuration failure and its cause.
    this(string message, Throwable cause)
    {
        super(message, cause);
    }
}
