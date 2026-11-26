/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/ProxyConfig.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/AopConfigException.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.framework;

import flint.core : NestedRuntimeException;
import flint.java.lang : IllegalArgumentException;

@safe:

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
