// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/DispatcherServletRegistrationBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: a `DispatcherServlet` over empty strategies stands in for `new DispatcherServlet()`;
// Boot's null-path check and its refusal to change the mappings wait behind FlintDispatcherServletRegistrationChecks.
module dispatcher_servlet_registration_bean_test;

import flint.boot.webmvc.autoconfigure : DispatcherServletRegistrationBean;
import flint.web.servlet : DispatcherServlet, DispatcherStrategies;

@safe:

private DispatcherServlet newDispatcherServlet()
{
    return new DispatcherServlet(DispatcherStrategies.init);
}

// Boot rejects a null path, and its DispatcherServletRegistrationBean refuses setUrlMappings and addUrlMappings;
// Flint maps a null path to "/" and lets the mappings change.
version (FlintDispatcherServletRegistrationChecks)
{
    @("DispatcherServletRegistrationBeanTests.createWhenPathIsNullThrowsException") unittest
    {
        import flint.java.lang : IllegalArgumentException;
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            new DispatcherServletRegistrationBean(newDispatcherServlet(), null);
        catch (IllegalArgumentException e)
            thrown = e.msg.canFind("'path' must not be null");
        assert(thrown);
    }

    @("DispatcherServletRegistrationBeanTests.setUrlMappingsCannotBeCalled") unittest
    {
        import flint.java.lang : UnsupportedOperationException;
        import std.exception : assertThrown;

        auto bean = new DispatcherServletRegistrationBean(newDispatcherServlet(), "/test");
        assertThrown!UnsupportedOperationException(bean.setUrlMappings([]));
    }

    @("DispatcherServletRegistrationBeanTests.addUrlMappingsCannotBeCalled") unittest
    {
        import flint.java.lang : UnsupportedOperationException;
        import std.exception : assertThrown;

        auto bean = new DispatcherServletRegistrationBean(newDispatcherServlet(), "/test");
        assertThrown!UnsupportedOperationException(bean.addUrlMappings("/test"));
    }
}

@("DispatcherServletRegistrationBeanTests.getPathReturnsPath") unittest
{
    auto bean = new DispatcherServletRegistrationBean(newDispatcherServlet(), "/test");
    assert(bean.getPath() == "/test");
}

@("DispatcherServletRegistrationBeanTests.getUrlMappingsReturnsSinglePathMappedPattern") unittest
{
    auto bean = new DispatcherServletRegistrationBean(newDispatcherServlet(), "/test");
    assert(bean.getUrlMappings() == ["/test/*"]);
}
