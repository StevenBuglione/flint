module autoproxy_constants_tests;

import flint.aop.framework.autoproxy : AutoProxyUtils;

@safe:

@("Auto-proxy configuration uses the qualified Flint bean and attribute names") unittest
{
    assert(AutoProxyUtils.DEFAULT_PROXY_CONFIG_BEAN_NAME == "flint.aop.framework.autoproxy.defaultProxyConfig");
    assert(
            AutoProxyUtils.EXPOSED_INTERFACES_ATTRIBUTE
            == "flint.aop.framework.autoproxy.AutoProxyUtils.exposedInterfaces");
    assert(AutoProxyUtils.ORIGINAL_TARGET_CLASS_ATTRIBUTE
            == "flint.aop.framework.autoproxy.AutoProxyUtils.originalTargetClass");
    assert(AutoProxyUtils.PRESERVE_TARGET_CLASS_ATTRIBUTE
            == "flint.aop.framework.autoproxy.AutoProxyUtils.preserveTargetClass");
}
