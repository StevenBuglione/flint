// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/web/servlet/DelegatingFilterProxyRegistrationBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the test methods web_server_test.d does not port (it holds
// targetBeanNameMustNotBeEmpty, nameDefaultsToTargetBeanName, getFilterUsesDelegatingFilterProxy and
// initShouldNotCauseEarlyInitialization), with the tests inherited from AbstractFilterRegistrationBeanTests (mixed in
// from abstract_filter_registration_bean_tests.d); a null `String` target bean name is D's null string, which is
// empty; the proxy is private, so it is recognised by its class name. Not ported:
// createServletRegistrationBeanMustNotBeNull (a null array is the empty slice in D).
module delegating_filter_proxy_registration_bean_upstream_test;

import abstract_filter_registration_bean_tests : AbstractFilterRegistrationBeanTests;
import flint.boot.web.server.servlet : DelegatingFilterProxyRegistrationBean, ServletRegistrationBean;
import flint.context.support : GenericApplicationContext;
import flint.jakarta.servlet : Filter;

@safe:

private GenericApplicationContext applicationContext;

static this()
{
    applicationContext = new GenericApplicationContext;
}

private DelegatingFilterProxyRegistrationBean createFilterRegistrationBean(
        ServletRegistrationBean[] servletRegistrationBeans...)
{
    auto bean = new DelegatingFilterProxyRegistrationBean("mockFilter", servletRegistrationBeans);
    bean.setApplicationContext(applicationContext);
    return bean;
}

private bool isExpectedFilter(Filter candidate)
{
    import std.algorithm.searching : endsWith;

    return typeid(cast(Object) candidate).name.endsWith(".DelegatingFilterProxy");
}

mixin AbstractFilterRegistrationBeanTests!"DelegatingFilterProxyRegistrationBeanTests";

@("DelegatingFilterProxyRegistrationBeanTests.targetBeanNameMustNotBeNull") unittest
{
    import flint.java.lang : IllegalArgumentException;
    import std.algorithm.searching : canFind;

    bool thrown;
    try
        new DelegatingFilterProxyRegistrationBean(null);
    catch (IllegalArgumentException e)
        thrown = e.msg.canFind("'targetBeanName' must not be empty");
    assert(thrown);
}
