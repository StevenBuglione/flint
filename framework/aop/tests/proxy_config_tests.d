module proxy_config_tests;

import std.exception : assertThrown;

import flint.aop.framework : AopConfigException, ProxyConfig;
import flint.core : NestedRuntimeException;
import flint.java.lang : IllegalArgumentException;

@safe:

private void enableFlags(ProxyConfig config)
{
    config.setProxyTargetClass(true);
    config.setOptimize(true);
    config.setOpaque(true);
    config.setExposeProxy(true);
    config.setFrozen(true);
}

@("Proxy configuration distinguishes unset flags from explicit false") unittest
{
    auto config = new ProxyConfig;
    assert(!config.isProxyTargetClass() && !config.isOptimize() && !config.isOpaque());
    assert(!config.isExposeProxy() && !config.isFrozen());
    enum unset = "proxyTargetClass=null; optimize=null; opaque=null; exposeProxy=null; frozen=null";
    assert(config.toString() == unset);

    enableFlags(config);
    assert(config.isProxyTargetClass() && config.isOptimize() && config.isOpaque());
    assert(config.isExposeProxy() && config.isFrozen());
    enum enabled = "proxyTargetClass=true; optimize=true; opaque=true; exposeProxy=true; frozen=true";
    assert(config.toString() == enabled);

    config.setProxyTargetClass(false);
    config.setOptimize(false);
    config.setOpaque(false);
    config.setExposeProxy(false);
    config.setFrozen(false);
    enum disabled = "proxyTargetClass=false; optimize=false; opaque=false; exposeProxy=false; frozen=false";
    assert(config.toString() == disabled);
}

@("copyDefault fills only unset flags and retains an unset source flag") unittest
{
    auto config = new ProxyConfig;
    config.setProxyTargetClass(false);
    config.setOpaque(true);
    auto partialDefaults = new ProxyConfig;
    partialDefaults.setOptimize(false);
    partialDefaults.setOpaque(false);
    partialDefaults.setFrozen(true);

    config.copyDefault(partialDefaults);
    assert(!config.isProxyTargetClass() && !config.isOptimize() && config.isOpaque());
    assert(config.isFrozen());
    enum partial = "proxyTargetClass=false; optimize=false; opaque=true; exposeProxy=null; frozen=true";
    assert(config.toString() == partial);

    auto allDefaults = new ProxyConfig;
    enableFlags(allDefaults);
    config.copyDefault(allDefaults);
    enum merged = "proxyTargetClass=false; optimize=false; opaque=true; exposeProxy=true; frozen=true";
    assert(config.toString() == merged);
}

@("copyFrom replaces all previous flags, including those unset on the source") unittest
{
    auto config = new ProxyConfig;
    enableFlags(config);
    auto source = new ProxyConfig;
    source.setOptimize(false);
    source.setExposeProxy(true);

    config.copyFrom(source);
    assert(config.toString() == source.toString());
    source.setOptimize(true);
    source.setExposeProxy(false);
    enum copy = "proxyTargetClass=null; optimize=false; opaque=null; exposeProxy=true; frozen=null";
    assert(config.toString() == copy);

    config.copyDefault(source);
    assert(config.toString() == copy);
    assertThrown!IllegalArgumentException(config.copyFrom(null));
    assertThrown!IllegalArgumentException(config.copyDefault(null));
    assert(config.toString() == copy);
}

@("AopConfigException preserves its message and optional nested cause") unittest
{
    NestedRuntimeException invalid = new AopConfigException("invalid proxy configuration");
    assert(invalid.msg == "invalid proxy configuration");
    assert(invalid.getRootCause() is null && invalid.getMostSpecificCause() is invalid);

    auto cause = new IllegalArgumentException("invalid advisor");
    auto wrapped = new AopConfigException("invalid proxy configuration", cause);
    assert(wrapped.msg == invalid.msg);
    assert(wrapped.getRootCause() is cause && wrapped.getMostSpecificCause() is cause);
}
