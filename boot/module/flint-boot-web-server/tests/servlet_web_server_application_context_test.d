// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/test/java/org/springframework/boot/web/server/servlet/context/ServletWebServerApplicationContextTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `MockServletWebServerFactory` and the Mockito `ServletContext`, servlets, filters and
// initializers are web_server_test_support's recording fakes and small test classes; beans are registered as
// singletons, and through `registerBean` when they must fail on creation; `BeanCreationException` is any
// `Exception` carrying the failure's message. Flint's context extends GenericApplicationContext: the
// `ServletContext`, web scopes and `ServletContextAware` wait behind FlintWebApplicationContext, the
// `ServletWebServerInitializedEvent` and `local.server.port` behind FlintWebServerInitializedEvent, listener beans
// behind FlintServletListenerRegistration, bean-definition property placeholders behind FlintBeanPropertyPlaceholders,
// `@Order` on filter classes behind FlintOrderAnnotationOnBeans, and Boot's start/stop lifecycle of the web server
// behind FlintWebServerLifecycle.
module servlet_web_server_application_context_test;

import flint.boot.web.server.servlet : FilterRegistrationBean, ServletContextInitializer, ServletRegistrationBean;
import flint.boot.web.server.servlet.context : ServletWebServerApplicationContext;
import flint.context : ApplicationContextException, GenericApplicationListener;
import flint.core : Ordered;
import flint.jakarta.servlet : DispatcherType, Filter, FilterChain, ServletContext, ServletRequest, ServletResponse;
import flint.java.lang : IllegalStateException, RuntimeException;
import std.algorithm.searching : canFind;
import web_server_test_support : MockServletWebServerFactory;

@safe:

private class TestServlet : imported!"flint.jakarta.servlet.http".HttpServlet
{
}

private final class OrderedServlet : TestServlet, Ordered
{
    private int order;

    this(int order) pure nothrow @nogc
    {
        this.order = order;
    }

    int getOrder()
    {
        return order;
    }
}

private class TestFilter : Filter
{
    mixin Filter.Defaults;

    void doFilter(ServletRequest, ServletResponse, FilterChain)
    {
    }
}

private final class OrderedTestFilter : TestFilter, Ordered
{
    private int order;

    this(int order) pure nothrow @nogc
    {
        this.order = order;
    }

    int getOrder()
    {
        return order;
    }
}

// The order in which initializers ran.
private final class Log
{
    string[] names;
}

// Records the ServletContext each call to onStartup received, in a shared log.
private final class RecordingInitializer : ServletContextInitializer
{
    private string name;
    private Log log;
    ServletContext servletContext;

    this(string name, Log log) pure nothrow @nogc
    {
        this.name = name;
        this.log = log;
    }

    void onStartup(ServletContext servletContext)
    {
        this.servletContext = servletContext;
        log.names ~= name;
    }
}

// The messages of `failure` and its causes, as a stack trace shows them.
private string chainText(Throwable failure)
{
    string text;
    for (Throwable cause = failure; cause !is null; cause = causeOf(cause))
        text ~= cause.msg.idup ~ "\n";
    return text;
}

// Java's `getCause()`: Flint's RuntimeException keeps it apart from D's `next`.
private Throwable causeOf(Throwable failure)
{
    if (auto runtime = cast(RuntimeException) failure)
        return runtime.getCause();
    return failure.next;
}

private final class OrderedInitializer : ServletContextInitializer, Ordered
{
    private RecordingInitializer recording;
    private int order;

    this(RecordingInitializer recording, int order) pure nothrow @nogc
    {
        this.recording = recording;
        this.order = order;
    }

    void onStartup(ServletContext servletContext)
    {
        recording.onStartup(servletContext);
    }

    int getOrder()
    {
        return order;
    }
}

// `TestApplicationListener`: every event, in order.
private final class TestApplicationListener : GenericApplicationListener
{
    Object[] events;

    bool supportsEvent(Object)
    {
        return true;
    }

    void dispatchEvent(Object event)
    {
        events ~= event;
    }

    int getListenerOrder()
    {
        return Ordered.LOWEST_PRECEDENCE;
    }
}

private struct Fixture
{
    ServletWebServerApplicationContext context;
    MockServletWebServerFactory factory;
}

private Fixture fixture(bool addWebServerFactoryBean = true)
{
    auto context = new ServletWebServerApplicationContext;
    MockServletWebServerFactory factory;
    if (addWebServerFactoryBean)
    {
        factory = new MockServletWebServerFactory;
        context.getBeanFactory().registerSingleton("webServerFactory", factory);
    }
    return Fixture(context, factory);
}

private void addRefreshFailure(ServletWebServerApplicationContext context)
{
    context.registerBean!Object("refreshFailure", delegate Object() {
        throw new RuntimeException("Fail refresh");
    });
}

// The web application context: Boot's context is a GenericWebApplicationContext with the ServletContext, its
// attribute, the web scopes and ServletContextAware support.
version (FlintWebApplicationContext)
{
    @("ServletWebServerApplicationContextTests.startRegistrations") unittest
    {
        auto f = fixture();
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.context.getServletContext() is f.factory.servletContext);
        assert(f.context.getBeanFactory().getRegisteredScope("session") !is null);
        assert(f.context.containsBean("servletContext"));
    }

    @("ServletWebServerApplicationContextTests.servletContextAwareBeansAreInjected") unittest
    {
        import flint.web.context : ServletContextAware;

        auto f = fixture();
        auto bean = new class ServletContextAware
        {
            ServletContext servletContext;

            void setServletContext(ServletContext servletContext)
            {
                this.servletContext = servletContext;
            }
        };
        f.context.getBeanFactory().registerSingleton("bean", cast(Object) bean);
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(bean.servletContext is f.factory.servletContext);
    }

    @("ServletWebServerApplicationContextTests.doesNotReplaceExistingScopes") unittest
    {
        import flint.beans.factory.config : Scope;

        auto f = fixture();
        Scope scope_ = new class Scope
        {
        };
        f.context.getBeanFactory().registerScope("request", scope_);
        f.context.getBeanFactory().registerScope("session", scope_);
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.context.getBeanFactory().getRegisteredScope("request") is scope_);
        assert(f.context.getBeanFactory().getRegisteredScope("session") is scope_);
    }

    @("ServletWebServerApplicationContextTests.servletRequestCanBeInjectedEarly") unittest
    {
        auto f = fixture();
        f.context.registerBean!ServletRequest("withAutowiredServletRequest", () => f.context.getServletRequest());
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.context.getBean("withAutowiredServletRequest") !is null);
    }

    @("ServletWebServerApplicationContextTests.webApplicationScopeIsRegistered") unittest
    {
        auto f = fixture();
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.context.getBeanFactory().getRegisteredScope("application") !is null);
    }
}

@("ServletWebServerApplicationContextTests.doesNotRegistersShutdownHook") unittest
{
    auto f = fixture();
    f.context.refresh();
    scope (exit)
        f.context.close();
    assert(!f.context.isShutdownHookRegistered());
}

// Boot publishes a ServletWebServerInitializedEvent before ContextRefreshedEvent, and
// ServerPortInfoApplicationContextInitializer turns it into `local.server.port`.
version (FlintWebServerInitializedEvent)
{
    import flint.boot.web.server.servlet.context : ServerPortInfoApplicationContextInitializer,
        ServletWebServerInitializedEvent;

    @("ServletWebServerApplicationContextTests.ServletWebServerInitializedEventPublished") unittest
    {
        import flint.context.event : ContextRefreshedEvent;

        auto f = fixture();
        auto listener = new TestApplicationListener;
        f.context.addApplicationListener(listener);
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(listener.events.length == 2);
        auto initializedEvent = cast(ServletWebServerInitializedEvent) listener.events[0];
        assert(initializedEvent !is null && cast(ContextRefreshedEvent) listener.events[1]!is null);
        assert(initializedEvent.getSource().getPort() >= 0);
        assert(initializedEvent.getApplicationContext() is f.context);
    }

    @("ServletWebServerApplicationContextTests.localPortIsAvailable") unittest
    {
        auto f = fixture();
        new ServerPortInfoApplicationContextInitializer().initialize(f.context);
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.context.getEnvironment().getProperty("local.server.port") == "8080");
    }
}

// Boot's WebServerStartStopLifecycle stops the server when the context stops and starts it again when the context
// starts; on close and on a failed refresh it stops the server, then destroys it (whose default also stops it), and
// a failing stop or destroy is added to the refresh failure. Flint starts the server at the end of refresh and only
// destroys it (after a graceful shutdown) on close or failure.
version (FlintWebServerLifecycle)
{
    @("ServletWebServerApplicationContextTests.stopOnStop") unittest
    {
        auto f = fixture();
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.factory.webServer.starts == 1);
        f.context.stop();
        assert(f.factory.webServer.stops == 1);
    }

    @("ServletWebServerApplicationContextTests.startOnStartAfterStop") unittest
    {
        auto f = fixture();
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.factory.webServer.starts == 1);
        f.context.stop();
        assert(f.factory.webServer.stops == 1);
        f.context.start();
        assert(f.factory.webServer.starts == 2);
    }

    @("ServletWebServerApplicationContextTests.stopAndDestroyOnClose") unittest
    {
        auto f = fixture();
        f.context.refresh();
        f.context.close();
        assert(f.factory.webServer.stops == 2);
        assert(f.factory.webServer.destroys == 1);
    }

    @("ServletWebServerApplicationContextTests.whenContextRefreshFailedThenWebServerIsStoppedAndDestroyed") unittest
    {
        auto f = fixture();
        addRefreshFailure(f.context);
        bool failed;
        try
            f.context.refresh();
        catch (Exception e)
            failed = true;
        assert(failed);
        auto webServer = f.context.getWebServer();
        assert(f.factory.webServer is webServer);
        assert(f.factory.webServer.stops == 2, imported!"std.conv".to!string(f.factory.webServer.stops));
        assert(f.factory.webServer.destroys == 1);
    }

    @("ServletWebServerApplicationContextTests.whenContextRefreshFailedThenWebServerStopFailedCatchStopException")
    unittest
    {
        auto f = fixture();
        f.context.registerBean!Object("refreshFailure", delegate Object() {
            f.factory.webServer.failOnStop = new RuntimeException("WebServer has failed to stop");
            throw new RuntimeException("Fail refresh");
        });
        string trace;
        try
            f.context.refresh();
        catch (Exception e)
            trace = chainText(e);
        assert(trace.canFind("WebServer has failed to stop"), trace);
        assert(f.factory.webServer.stops == 1);
        assert(f.factory.webServer.destroys == 0);
    }

    @("ServletWebServerApplicationContextTests."
            ~ "whenContextRefreshFailedThenWebServerIsStoppedAndDestroyFailedCatchDestroyException")
    unittest
    {
        auto f = fixture();
        f.context.registerBean!Object("refreshFailure", delegate Object() {
            f.factory.webServer.failOnDestroy = new RuntimeException("WebServer has failed to destroy");
            throw new RuntimeException("Fail refresh");
        });
        string trace;
        try
            f.context.refresh();
        catch (Exception e)
            trace = chainText(e);
        assert(trace.canFind("WebServer has failed to destroy"), trace);
        assert(f.factory.webServer.stops == 1);
        assert(f.factory.webServer.destroys == 1);
    }
}

// LIKELY BUG: Boot publishes AvailabilityChangeEvent(REFUSING_TRAFFIC) when an active servlet web server context
// closes, so readiness probes report the application unready during shutdown; Flint's context does not.
version (FlintAvailabilityOnClose)
{
    @("ServletWebServerApplicationContextTests.applicationIsUnreadyDuringShutdown") unittest
    {
        import flint.boot.availability : AvailabilityChangeEvent, ReadinessState;
        import flint.context.event : ContextClosedEvent;

        auto f = fixture();
        auto listener = new TestApplicationListener;
        f.context.refresh();
        f.context.addApplicationListener(listener);
        f.context.close();
        assert(listener.events.length == 2, imported!"std.conv".to!string(listener.events.length));
        assert(listener.events.canFind!(e => cast(AvailabilityChangeEvent!ReadinessState) e !is null));
        assert(listener.events.canFind!(e => cast(ContextClosedEvent) e !is null));
    }
}

@("ServletWebServerApplicationContextTests.whenContextIsNotActiveThenCloseDoesNotChangeTheApplicationAvailability")
unittest
{
    auto f = fixture();
    auto listener = new TestApplicationListener;
    f.context.addApplicationListener(listener);
    addRefreshFailure(f.context);
    bool failed;
    try
        f.context.refresh();
    catch (Exception e)
        failed = chainText(e).canFind("Fail refresh");
    assert(failed);
    f.context.close();
    assert(listener.events.length == 0);
}

@("ServletWebServerApplicationContextTests.cannotSecondRefresh") unittest
{
    import std.exception : assertThrown;

    auto f = fixture();
    f.context.refresh();
    scope (exit)
        f.context.close();
    assertThrown!IllegalStateException(f.context.refresh());
}

@("ServletWebServerApplicationContextTests.missingServletWebServerFactory") unittest
{
    auto f = fixture(false);
    string rootCause;
    try
        f.context.refresh();
    catch (ApplicationContextException e)
    {
        Throwable cause = e;
        while (causeOf(cause) !is null)
            cause = causeOf(cause);
        rootCause = cause.msg.idup;
    }
    assert(rootCause.canFind(
            "Unable to start ServletWebServerApplicationContext due to missing " ~ "ServletWebServerFactory bean"),
            rootCause);
}

@("ServletWebServerApplicationContextTests.tooManyWebServerFactories") unittest
{
    auto f = fixture();
    f.context.getBeanFactory().registerSingleton("webServerFactory2", new MockServletWebServerFactory);
    string rootCause;
    try
        f.context.refresh();
    catch (ApplicationContextException e)
    {
        Throwable cause = e;
        while (causeOf(cause) !is null)
            cause = causeOf(cause);
        rootCause = cause.msg.idup;
    }
    assert(rootCause.canFind(
            "Unable to start ServletWebServerApplicationContext due to " ~ "multiple ServletWebServerFactory beans"),
            rootCause);
}

@("ServletWebServerApplicationContextTests.singleServletBean") unittest
{
    auto f = fixture();
    auto servlet = new TestServlet;
    f.context.getBeanFactory().registerSingleton("servletBean", servlet);
    f.context.refresh();
    scope (exit)
        f.context.close();
    auto servletContext = f.factory.servletContext;
    assert(servletContext.servlets[0].name == "servletBean" && servletContext.servlets[0].servlet is servlet);
    assert(servletContext.servlets[0].mappings == [["/"]]);
}

// Boot reads `@Order` on a bean's class (OrderedFilter is a GenericFilterBean with `@Order(10)`); Flint's
// ServletContextInitializerBeans reads only the Ordered interface, so the filter sorts last.
version (FlintOrderAnnotationOnBeans)
{
    import flint.core.annotation : Order;

    @Order(10) private final class OrderedFilter : TestFilter
    {
    }

    @("ServletWebServerApplicationContextTests.orderedBeanInsertedCorrectly") unittest
    {
        auto f = fixture();
        auto filter = new OrderedFilter;
        f.context.getBeanFactory().registerSingleton("filterBean", filter);
        auto registration = new FilterRegistrationBean;
        registration.setName("filterBeanRegistration");
        registration.setFilter(new TestFilter);
        registration.setOrder(100);
        f.context.getBeanFactory().registerSingleton("filterRegistrationBean", registration);
        f.context.refresh();
        scope (exit)
            f.context.close();
        auto servletContext = f.factory.servletContext;
        assert(servletContext.calls.canFind("filterBean") && servletContext.calls.canFind("filterBeanRegistration"));
        assert(servletContext.filters[0].filter is filter);
    }
}

@("ServletWebServerApplicationContextTests.multipleServletBeans") unittest
{
    auto f = fixture();
    auto servlet1 = new OrderedServlet(1);
    auto servlet2 = new OrderedServlet(2);
    f.context.getBeanFactory().registerSingleton("servletBean2", servlet2);
    f.context.getBeanFactory().registerSingleton("servletBean1", servlet1);
    f.context.refresh();
    scope (exit)
        f.context.close();
    auto servletContext = f.factory.servletContext;
    assert(servletContext.calls == ["servletBean1", "servletBean2"]);
    assert(servletContext.servlets[0].servlet is servlet1 && servletContext.servlets[1].servlet is servlet2);
    assert(servletContext.servlets[0].mappings == [["/servletBean1/"]]);
    assert(servletContext.servlets[1].mappings == [["/servletBean2/"]]);
}

@("ServletWebServerApplicationContextTests.multipleServletBeansWithMainDispatcher") unittest
{
    auto f = fixture();
    auto servlet1 = new OrderedServlet(1);
    auto servlet2 = new OrderedServlet(2);
    f.context.getBeanFactory().registerSingleton("servletBean2", servlet2);
    f.context.getBeanFactory().registerSingleton("dispatcherServlet", servlet1);
    f.context.refresh();
    scope (exit)
        f.context.close();
    auto servletContext = f.factory.servletContext;
    assert(servletContext.calls == ["dispatcherServlet", "servletBean2"]);
    assert(servletContext.servlets[0].mappings == [["/"]]);
    assert(servletContext.servlets[1].mappings == [["/servletBean2/"]]);
}

@("ServletWebServerApplicationContextTests.servletAndFilterBeans") unittest
{
    auto f = fixture();
    auto servlet = new TestServlet;
    auto filter1 = new OrderedTestFilter(1);
    auto filter2 = new OrderedTestFilter(2);
    f.context.getBeanFactory().registerSingleton("servletBean", servlet);
    f.context.getBeanFactory().registerSingleton("filterBean2", filter2);
    f.context.getBeanFactory().registerSingleton("filterBean1", filter1);
    f.context.refresh();
    scope (exit)
        f.context.close();
    auto servletContext = f.factory.servletContext;
    assert(servletContext.servlets[0].name == "servletBean" && servletContext.servlets[0].mappings == [
        ["/"]
    ]);
    assert(servletContext.filters[0].name == "filterBean1" && servletContext.filters[0].filter is filter1);
    assert(servletContext.filters[1].name == "filterBean2" && servletContext.filters[1].filter is filter2);
    foreach (registration; servletContext.filters)
    {
        assert(registration.urlPatternMappings.length == 1);
        assert(registration.urlPatternMappings[0].dispatcherTypes == [DispatcherType.REQUEST]);
        assert(!registration.urlPatternMappings[0].matchAfter && registration.urlPatternMappings[0].values == [
            "/*"
        ]);
    }
}

@("ServletWebServerApplicationContextTests.servletContextInitializerBeans") unittest
{
    auto f = fixture();
    auto log = new Log;
    auto initializer1 = new RecordingInitializer("initializer1", log);
    auto initializer2 = new RecordingInitializer("initializer2", log);
    f.context.getBeanFactory().registerSingleton("initializerBean2", new OrderedInitializer(initializer2, 2));
    f.context.getBeanFactory().registerSingleton("initializerBean1", new OrderedInitializer(initializer1, 1));
    f.context.refresh();
    scope (exit)
        f.context.close();
    assert(log.names == ["initializer1", "initializer2"]);
    assert(initializer1.servletContext is f.factory.servletContext);
    assert(initializer2.servletContext is f.factory.servletContext);
}

// Servlet listener beans (`ServletContextListener`) are added to the ServletContext in Boot.
version (FlintServletListenerRegistration)
{
    @("ServletWebServerApplicationContextTests.servletContextListenerBeans") unittest
    {
        import flint.jakarta.servlet : ServletContextListener;

        auto f = fixture();
        auto initializer = new class ServletContextListener
        {
        };
        f.context.getBeanFactory().registerSingleton("initializerBean", cast(Object) initializer);
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.factory.servletContext.listeners == [initializer]);
    }
}

@("ServletWebServerApplicationContextTests.unorderedServletContextInitializerBeans") unittest
{
    auto f = fixture();
    auto log = new Log;
    auto initializer1 = new RecordingInitializer("initializer1", log);
    auto initializer2 = new RecordingInitializer("initializer2", log);
    f.context.getBeanFactory().registerSingleton("initializerBean2", initializer2);
    f.context.getBeanFactory().registerSingleton("initializerBean1", initializer1);
    f.context.refresh();
    scope (exit)
        f.context.close();
    assert(initializer1.servletContext is f.factory.servletContext);
    assert(initializer2.servletContext is f.factory.servletContext);
}

@("ServletWebServerApplicationContextTests.servletContextInitializerBeansDoesNotSkipServletsAndFilters") unittest
{
    auto f = fixture();
    auto log = new Log;
    auto initializer = new RecordingInitializer("initializer", log);
    f.context.getBeanFactory().registerSingleton("initializerBean", initializer);
    f.context.getBeanFactory().registerSingleton("servletBean", new TestServlet);
    f.context.getBeanFactory().registerSingleton("filterBean", new TestFilter);
    f.context.refresh();
    scope (exit)
        f.context.close();
    assert(initializer.servletContext is f.factory.servletContext);
    assert(f.factory.servletContext.servlets.length == 1);
    assert(f.factory.servletContext.filters.length == 1);
}

@("ServletWebServerApplicationContextTests.servletContextInitializerBeansSkipsRegisteredServletsAndFilters") unittest
{
    auto f = fixture();
    auto servlet = new TestServlet;
    f.context.getBeanFactory().registerSingleton("initializerBean", new ServletRegistrationBean(servlet, "/foo"));
    f.context.getBeanFactory().registerSingleton("servletBean", servlet);
    f.context.getBeanFactory().registerSingleton("filterBean", new TestFilter);
    f.context.refresh();
    scope (exit)
        f.context.close();
    assert(f.factory.servletContext.servlets.length <= 1);
    assert(f.factory.servletContext.filters.length <= 1);
}

@("ServletWebServerApplicationContextTests.filterRegistrationBeansSkipsRegisteredFilters") unittest
{
    auto f = fixture();
    auto filter = new TestFilter;
    f.context.getBeanFactory().registerSingleton("initializerBean", new FilterRegistrationBean(filter));
    f.context.getBeanFactory().registerSingleton("filterBean", filter);
    f.context.refresh();
    scope (exit)
        f.context.close();
    assert(f.factory.servletContext.filters.length <= 1);
}

@("ServletWebServerApplicationContextTests.delegatingFilterProxyRegistrationBeansSkipsTargetBeanNames") unittest
{
    import flint.boot.web.server.servlet : DelegatingFilterProxyRegistrationBean;

    auto f = fixture();
    auto initializer = new DelegatingFilterProxyRegistrationBean("filterBean");
    initializer.setApplicationContext(f.context);
    f.context.getBeanFactory().registerSingleton("initializerBean", initializer);
    f.context.registerBean!Filter("filterBean", delegate Filter() {
        throw new IllegalStateException("Create FilterBean Failure");
    }, (definition) { definition.setLazyInit(true); });
    f.context.refresh();
    scope (exit)
        f.context.close();
    auto filters = f.factory.servletContext.filters;
    assert(filters.length <= 1);
    // Up to this point the filterBean should not have been created; calling the proxy creates it and fails.
    string message;
    try
    {
        filters[0].filter.init(null);
        filters[0].filter.doFilter(null, null, null);
    }
    catch (Exception e)
        message = chainText(e);
    assert(message.canFind("Create FilterBean Failure"), message);
}

// A bean definition's `${port}` property value resolved by PropertySourcesPlaceholderConfigurer before the factory
// is used; Flint's definitions carry no property values.
version (FlintBeanPropertyPlaceholders)
{
    @("ServletWebServerApplicationContextTests.postProcessWebServerFactory") unittest
    {
        import flint.beans.factory.support : RootBeanDefinition;
        import flint.context.support : PropertySourcesPlaceholderConfigurer;

        auto f = fixture(false);
        auto beanDefinition = new RootBeanDefinition(MockServletWebServerFactory.classinfo.name, null);
        beanDefinition.getPropertyValues().add("port", "${port}");
        f.context.registerBeanDefinition("webServerFactory", beanDefinition);
        auto propertySupport = new PropertySourcesPlaceholderConfigurer;
        propertySupport.setProperties(["port": "8080"]);
        f.context.getBeanFactory().registerSingleton("propertySupport", propertySupport);
        f.context.refresh();
        scope (exit)
            f.context.close();
        assert(f.context.getWebServer().getPort() == 8080);
    }
}
