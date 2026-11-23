// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/web/servlet/ServletContextInitializerBeansTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the `@Configuration` classes' beans are registered as singletons of a
// ServletWebServerApplicationContext, which Flint's `ServletContextInitializerBeans` reads, instead of loading an
// AnnotationConfigApplicationContext. The initializer-type filter waits behind FlintInitializerBeansTypes, listener
// beans behind FlintServletListenerRegistration, the `@ServletRegistration` and `@FilterRegistration` annotations
// behind FlintRegistrationAnnotations, and Boot's single registration of a servlet or filter that is itself a
// ServletContextInitializer behind FlintInitializerBeansDeduplication.
module servlet_context_initializer_beans_test;

import flint.boot.web.server.servlet : ServletContextInitializer, ServletRegistrationBean;
import flint.boot.web.server.servlet.context : ServletContextInitializerBeans, ServletWebServerApplicationContext;
import flint.jakarta.servlet : Filter, FilterChain, ServletContext, ServletRequest, ServletResponse;
import flint.jakarta.servlet.http : HttpServlet;

@safe:

// `TestServlet`.
private class TestServlet : HttpServlet, ServletContextInitializer
{
    void onStartup(ServletContext)
    {
    }
}

// `OrderedTestServlet`.
private final class OrderedTestServlet : HttpServlet, ServletContextInitializer, imported!"flint.core".Ordered
{
    enum ORDER = 3;

    void onStartup(ServletContext)
    {
    }

    int getOrder()
    {
        return ORDER;
    }
}

// `TestFilter`.
private final class TestFilter : Filter, ServletContextInitializer
{
    mixin Filter.Defaults;

    void onStartup(ServletContext)
    {
    }

    void doFilter(ServletRequest, ServletResponse, FilterChain)
    {
    }
}

// `TestServletContextInitializer`.
private final class TestServletContextInitializer : ServletContextInitializer
{
    void onStartup(ServletContext)
    {
    }
}

private ServletWebServerApplicationContext load(Object[string] beans)
{
    auto context = new ServletWebServerApplicationContext;
    foreach (name, bean; beans)
        context.getBeanFactory().registerSingleton(name, bean);
    return context;
}

// LIKELY BUG: a servlet or filter bean that is also a ServletContextInitializer is used as the initializer and, in
// Flint, adapted again into a ServletRegistrationBean (or FilterRegistrationBean), so it is registered twice.
version (FlintInitializerBeansDeduplication)
{
    @("ServletContextInitializerBeansTests.servletThatImplementsServletContextInitializerIsOnlyRegisteredOnce")
    unittest
    {
        auto initializerBeans = new ServletContextInitializerBeans(load([
            "testServlet": new TestServlet
        ])).get();
        assert(initializerBeans.length == 1, imported!"std.conv".to!string(initializerBeans.length));
        assert(cast(TestServlet) initializerBeans[0]!is null);
    }

    @("ServletContextInitializerBeansTests.filterThatImplementsServletContextInitializerIsOnlyRegisteredOnce")
    unittest
    {
        auto initializerBeans = new ServletContextInitializerBeans(load([
            "testFilter": new TestFilter
        ])).get();
        assert(initializerBeans.length == 1, imported!"std.conv".to!string(initializerBeans.length));
        assert(cast(TestFilter) initializerBeans[0]!is null);
    }
}

// `new ServletContextInitializerBeans(beanFactory, TestServletContextInitializer.class)`: only initializers of the
// given types are used as they are; Flint's constructor takes no types.
version (FlintInitializerBeansTypes)
{
    @("ServletContextInitializerBeansTests.looksForInitializerBeansOfSpecifiedType") unittest
    {
        auto initializerBeans = new ServletContextInitializerBeans(
                load([
            "testServletContextInitializer": cast(Object) new TestServletContextInitializer,
            "otherTestServletContextInitializer": new TestServletContextInitializer
        ]), [typeid(TestServletContextInitializer)]).get();
        assert(initializerBeans.length == 1);
    }

    @("ServletContextInitializerBeansTests.shouldApplyOrderFromBean") unittest
    {
        auto initializerBeans = new ServletContextInitializerBeans(load([
            "testServlet": new OrderedTestServlet
        ]), [typeid(TestServletContextInitializer)]).get();
        assert(initializerBeans.length == 1);
        auto registration = cast(ServletRegistrationBean) initializerBeans[0];
        assert(registration !is null && registration.getOrder() == OrderedTestServlet.ORDER);
    }
}

// Servlet listener beans (`HttpSessionIdListener`, `ServletContextListener`) and ServletListenerRegistrationBean.
version (FlintServletListenerRegistration)
{
    import flint.boot.web.server.servlet : ServletListenerRegistrationBean;
    import flint.jakarta.servlet.http : HttpSessionIdListener;

    @("ServletContextInitializerBeansTests.whenAnHttpSessionIdListenerBeanIsDefinedThenARegistrationBeanIsCreatedForIt")
    unittest
    {
        auto initializerBeans = new ServletContextInitializerBeans(
                load([
            "httpSessionIdListener": cast(Object) new class HttpSessionIdListener
            {
                void sessionIdChanged(imported!"flint.jakarta.servlet.http".HttpSessionEvent, string)
                {
                }
            }

        ])).get();
        assert(initializerBeans.length == 1);
        auto registration = cast(ServletListenerRegistrationBean) initializerBeans[0];
        assert(cast(HttpSessionIdListener) registration.getListener() !is null);
    }

    @("ServletContextInitializerBeansTests.classesThatImplementMultipleInterfacesAreRegisteredForAllOfThem") unittest
    {
        auto initializerBeans = new ServletContextInitializerBeans(
                load([
            "testServletAndFilterAndListener": cast(Object) new TestServletAndFilterAndListener
        ])).get();
        assert(initializerBeans.length == 3);
        assert(cast(ServletListenerRegistrationBean) initializerBeans[2]!is null);
    }
}

// Boot's `@ServletRegistration` and `@FilterRegistration` on `@Bean` methods, and `@Order` on them.
version (FlintRegistrationAnnotations)
{
    import flint.boot.web.server.servlet : FilterRegistration, ServletRegistration;

    @("ServletContextInitializerBeansTests.shouldApplyServletRegistrationAnnotation") unittest
    {
        static assert(is(ServletRegistration));
    }

    @("ServletContextInitializerBeansTests.shouldApplyFilterRegistrationAnnotation") unittest
    {
        static assert(is(FilterRegistration));
    }

    @("ServletContextInitializerBeansTests.shouldApplyFilterRegistrationAnnotationWithDefaultDispatcherTypes")
    unittest
    {
        static assert(is(FilterRegistration));
    }

    @("ServletContextInitializerBeansTests.shouldApplyOrderFromOrderAnnotationOnBeanMethod") unittest
    {
        static assert(is(ServletRegistration));
    }

    @("ServletContextInitializerBeansTests.orderedInterfaceShouldTakePrecedenceOverOrderAnnotation") unittest
    {
        static assert(is(ServletRegistration));
    }

    @("ServletContextInitializerBeansTests.shouldApplyOrderFromOrderAttribute") unittest
    {
        static assert(ServletRegistration.init.order == 0);
    }
}
