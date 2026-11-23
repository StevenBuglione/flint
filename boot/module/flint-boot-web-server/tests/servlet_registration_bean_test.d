// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/web/servlet/ServletRegistrationBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the Mockito `ServletContext` and `ServletRegistration.Dynamic` are
// web_server_test_support's recording fakes; Flint's `ServletRegistrationBean` takes the servlet in its
// constructor (no `setServlet`). Not ported: setMappingMustNotBeNull, createMappingMustNotBeNull and
// addMappingMustNotBeNull (a null `String[]` is the empty slice in D, which Flint accepts as no mappings).
// Boot's async-supported default, init parameters, `addUrlMappings` and `alwaysMapUrl` wait behind
// FlintRegistrationBeanSettings and FlintRegistrationAsyncSupported, its refusal of a failed registration behind
// FlintRegistrationFailure, and its null checks behind FlintRegistrationNullChecks.
module servlet_registration_bean_test;

import flint.boot.web.server.servlet : ServletRegistrationBean;
import flint.jakarta.servlet.http : HttpServlet;
import web_server_test_support : RecordingServletContext;

@safe:

// `MockServlet`.
private final class MockServlet : HttpServlet
{
}

@("ServletRegistrationBeanTests.startupWithDefaults") unittest
{
    auto servlet = new MockServlet;
    auto servletContext = new RecordingServletContext;
    auto bean = new ServletRegistrationBean(servlet);
    bean.onStartup(servletContext);
    assert(servletContext.servlets.length == 1);
    assert(servletContext.servlets[0].name == "mockServlet" && servletContext.servlets[0].servlet is servlet);
    // LIKELY BUG: Boot registers servlets (and filters) as async-supported by default; Flint never calls
    // setAsyncSupported, so the container's default (false) applies.
    version (FlintRegistrationAsyncSupported)
        assert(servletContext.servlets[0].asyncSupported == [true]);
    assert(servletContext.servlets[0].mappings == [["/*"]]);
}

// LIKELY BUG: Boot throws when the container refuses a registration (a name already registered); Flint's
// `register` returns silently, so a second servlet or filter under the same name is dropped without notice.
version (FlintRegistrationFailure)
{
    @("ServletRegistrationBeanTests.failsWithDoubleRegistration") unittest
    {
        import flint.java.lang : IllegalStateException;

        auto bean = new ServletRegistrationBean(new MockServlet);
        bean.setName("double-registration");
        auto servletContext = new RecordingServletContext;
        servletContext.refuseRegistrations = true;
        string message;
        try
            bean.onStartup(servletContext);
        catch (IllegalStateException e)
            message = e.msg;
        assert(message == "Failed to register 'servlet double-registration' on "
                ~ "the servlet context. Possibly already registered?", message);
    }
}

// Boot's DynamicRegistrationBean settings (async support, init parameters) and ServletRegistrationBean's
// no-argument constructor, `setServlet`, `addUrlMappings` and `alwaysMapUrl`.
version (FlintRegistrationBeanSettings)
{
    @("ServletRegistrationBeanTests.startupWithSpecifiedValues") unittest
    {
        auto servlet = new MockServlet;
        auto servletContext = new RecordingServletContext;
        auto bean = new ServletRegistrationBean;
        bean.setName("test");
        bean.setServlet(servlet);
        bean.setAsyncSupported(false);
        bean.setInitParameters(["a": "b"]);
        bean.addInitParameter("c", "d");
        bean.setUrlMappings(["/a", "/b"]);
        bean.addUrlMappings("/c");
        bean.setLoadOnStartup(10);
        bean.onStartup(servletContext);
        const registration = servletContext.servlets[0];
        assert(registration.name == "test" && registration.servlet is servlet);
        assert(registration.asyncSupported == [false]);
        assert(registration.initParameters == ["a": "b", "c": "d"]);
        assert(registration.mappings == [["/a", "/b", "/c"]]);
        assert(registration.loadOnStartup == [10]);
    }

    @("ServletRegistrationBeanTests.modifyInitParameters") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = new ServletRegistrationBean(new MockServlet, "/a", "/b");
        bean.addInitParameter("a", "b");
        bean.getInitParameters()["a"] = "c";
        bean.onStartup(servletContext);
        assert(servletContext.servlets[0].initParameters == ["a": "c"]);
    }

    @("ServletRegistrationBeanTests.withoutDefaultMappings") unittest
    {
        auto servletContext = new RecordingServletContext;
        auto bean = new ServletRegistrationBean(new MockServlet, false);
        bean.onStartup(servletContext);
        assert(servletContext.servlets[0].mappings.length == 0);
    }
}

@("ServletRegistrationBeanTests.specificName") unittest
{
    auto servlet = new MockServlet;
    auto servletContext = new RecordingServletContext;
    auto bean = new ServletRegistrationBean(servlet);
    bean.setName("specificName");
    bean.onStartup(servletContext);
    assert(servletContext.servlets[0].name == "specificName" && servletContext.servlets[0].servlet is servlet);
}

@("ServletRegistrationBeanTests.deducedName") unittest
{
    auto servlet = new MockServlet;
    auto servletContext = new RecordingServletContext;
    new ServletRegistrationBean(servlet).onStartup(servletContext);
    assert(servletContext.servlets[0].name == "mockServlet" && servletContext.servlets[0].servlet is servlet);
}

@("ServletRegistrationBeanTests.disable") unittest
{
    auto servletContext = new RecordingServletContext;
    auto bean = new ServletRegistrationBean(new MockServlet);
    bean.setEnabled(false);
    bean.onStartup(servletContext);
    assert(servletContext.calls.length == 0);
}

// Boot rejects a null servlet when the bean is created or started; Flint accepts it (and fails deducing its name).
version (FlintRegistrationNullChecks)
{
    @("ServletRegistrationBeanTests.setServletMustNotBeNull") unittest
    {
        import flint.java.lang : IllegalStateException;
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            new ServletRegistrationBean(null).onStartup(new RecordingServletContext);
        catch (IllegalStateException e)
            thrown = e.msg.canFind("Unable to return description for null servlet");
        assert(thrown);
    }

    @("ServletRegistrationBeanTests.createServletMustNotBeNull") unittest
    {
        import flint.java.lang : IllegalArgumentException;
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            new ServletRegistrationBean(null);
        catch (IllegalArgumentException e)
            thrown = e.msg.canFind("'servlet' must not be null");
        assert(thrown);
    }
}

@("ServletRegistrationBeanTests.setMappingReplacesValue") unittest
{
    auto servletContext = new RecordingServletContext;
    auto bean = new ServletRegistrationBean(new MockServlet, "/a", "/b");
    bean.setUrlMappings(["/c", "/d"]);
    bean.onStartup(servletContext);
    assert(servletContext.servlets[0].mappings == [["/c", "/d"]]);
}
