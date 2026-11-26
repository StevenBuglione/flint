/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/autoproxy/AutoProxyUtils.java
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/main/java/org/springframework/aop/framework/autoproxy/TargetSourceCreator.java
 * Copyright 2002-present the original author or authors.
 * SPDX-License-Identifier: Apache-2.0
 * Modified by the Flint authors.
 */
module flint.aop.framework.autoproxy;

import flint.aop : TargetSource;
import flint.engine.aot.descriptor : Descriptor;

@safe:

/// Selects beans that need a specialized target source, such as a pool.
interface TargetSourceCreator
{
    /// Returns a target source for the bean's AOT type and name, or null to decline it.
    TargetSource getTargetSource(const Descriptor beanClass, string beanName);
}

/// Common bean names and definition attributes for auto-proxying.
abstract class AutoProxyUtils
{
    private enum attributePrefix = __MODULE__ ~ ".AutoProxyUtils.";

    /// Bean name of the default proxy configuration.
    enum DEFAULT_PROXY_CONFIG_BEAN_NAME = __MODULE__ ~ ".defaultProxyConfig";

    /// Bean definition attribute selecting one or more interfaces to proxy.
    enum EXPOSED_INTERFACES_ATTRIBUTE = attributePrefix ~ "exposedInterfaces";

    /// Bean definition attribute indicating whether to preserve the target class.
    enum PRESERVE_TARGET_CLASS_ATTRIBUTE = attributePrefix ~ "preserveTargetClass";

    /// Bean definition attribute holding the original target class.
    enum ORIGINAL_TARGET_CLASS_ATTRIBUTE = attributePrefix ~ "originalTargetClass";
}
