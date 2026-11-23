// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/web/servlet/FilterRegistrationBeanTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: with the tests it inherits from AbstractFilterRegistrationBeanTests (mixed in from
// abstract_filter_registration_bean_tests.d); the Mockito `ServletContext` is web_server_test_support's recording
// fake; the anonymous `OncePerRequestFilter` is a class of that simple name, since Flint deduces the registered name
// from the class. Not ported: createServletRegistrationBeanMustNotBeNull (a null array is the empty slice in D).
module filter_registration_bean_test;

import abstract_filter_registration_bean_tests : AbstractFilterRegistrationBeanTests;
import flint.boot.web.server.servlet : FilterRegistrationBean, ServletRegistrationBean;
import flint.jakarta.servlet : DispatcherType, Filter, FilterChain, ServletRequest, ServletResponse;
import web_server_test_support : RecordingServletContext;

@safe:

// `MockFilter`.
private final class MockFilter : Filter
{
    mixin Filter.Defaults;

    void doFilter(ServletRequest, ServletResponse, FilterChain)
    {
    }
}

// The anonymous `OncePerRequestFilter` of the upstream test.
private final class OncePerRequestFilter : imported!"flint.web.filter".OncePerRequestFilter
{
    protected override void doFilterInternal(imported!"flint.jakarta.servlet.http".HttpServletRequest request,
            imported!"flint.jakarta.servlet.http".HttpServletResponse response, FilterChain filterChain)
    {
        filterChain.doFilter(request, response);
    }
}

private MockFilter filter;

static this()
{
    filter = new MockFilter;
}

private FilterRegistrationBean createFilterRegistrationBean(ServletRegistrationBean[] servletRegistrationBeans...)
{
    return new FilterRegistrationBean(filter, servletRegistrationBeans);
}

private bool isExpectedFilter(Filter candidate)
{
    return candidate is filter;
}

mixin AbstractFilterRegistrationBeanTests!"FilterRegistrationBeanTests";

@("FilterRegistrationBeanTests.setFilter") unittest
{
    auto servletContext = new RecordingServletContext;
    auto bean = new FilterRegistrationBean;
    bean.setFilter(filter);
    bean.onStartup(servletContext);
    assert(servletContext.filters[0].name == "mockFilter" && servletContext.filters[0].filter is filter);
}

// Boot rejects a null filter when the bean is created or started; Flint accepts it.
version (FlintRegistrationNullChecks)
{
    @("FilterRegistrationBeanTests.setFilterMustNotBeNull") unittest
    {
        import flint.java.lang : IllegalArgumentException;
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            new FilterRegistrationBean().onStartup(new RecordingServletContext);
        catch (IllegalArgumentException e)
            thrown = e.msg.canFind("'filter' must not be null");
        assert(thrown);
    }

    @("FilterRegistrationBeanTests.constructFilterMustNotBeNull") unittest
    {
        import flint.java.lang : IllegalArgumentException;
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            new FilterRegistrationBean(null);
        catch (IllegalArgumentException e)
            thrown = e.msg.canFind("'filter' must not be null");
        assert(thrown);
    }
}

@("FilterRegistrationBeanTests.startupWithOncePerRequestDefaults") unittest
{
    auto oncePerRequestFilter = new OncePerRequestFilter;
    auto servletContext = new RecordingServletContext;
    auto bean = new FilterRegistrationBean(oncePerRequestFilter);
    bean.onStartup(servletContext);
    assert(servletContext.filters[0].name == "oncePerRequestFilter");
    assert(servletContext.filters[0].filter is oncePerRequestFilter);
    version (FlintRegistrationAsyncSupported)
        assert(servletContext.filters[0].asyncSupported == [true]);
    import std.traits : EnumMembers;

    assert(servletContext.filters[0].urlPatternMappings[0].dispatcherTypes == [
        EnumMembers!DispatcherType
    ]);
    assert(!servletContext.filters[0].urlPatternMappings[0].matchAfter);
    assert(servletContext.filters[0].urlPatternMappings[0].values == ["/*"]);
}
