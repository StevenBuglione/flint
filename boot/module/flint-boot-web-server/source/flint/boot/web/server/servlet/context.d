// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/servlet/context/ServletWebServerApplicationContext.java
// with ServletWebServerApplicationContextFactory.java from the same directory, and
// core/spring-boot/src/main/java/org/springframework/boot/web/servlet/ServletContextInitializerBeans.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the context extends GenericApplicationContext (Flint has no
// GenericWebApplicationContext yet) and keeps the process alive until it is closed (deviation D-1); the server is
// started at the end of refresh, which Boot's WebServerStartStopLifecycle does; web scopes, ServletContextAware and
// the servlet-context resource loader follow with flint:web; the factory registers itself from this module's
// constructor where Boot lists it in spring.factories.

/// `org.springframework.boot.web.server.servlet.context`: the servlet web server application context.
module flint.boot.web.server.servlet.context;

import flint.boot : ApplicationContextFactory, DefaultApplicationContextFactory,
    KeepAliveApplicationContext, MainThreadHost, WebApplicationType;
import flint.boot.web.server : GracefulShutdownCallback, GracefulShutdownResult, HostedWebServer, WebServer;
import flint.boot.web.server.servlet : ServletContextInitializer, ServletWebServerFactory;
import flint.context : ApplicationContextException, ConfigurableApplicationContext;
import flint.context.support : GenericApplicationContext;

@safe:

/// An application context that creates, starts and stops an embedded servlet web server: the single
/// `ServletWebServerFactory` bean builds it, and every `ServletContextInitializer` bean (a `ServletRegistrationBean`,
/// for instance) configures its `ServletContext`.
class ServletWebServerApplicationContext : GenericApplicationContext, KeepAliveApplicationContext, MainThreadHost
{
    /// The name of the `DispatcherServlet` bean and registration.
    enum string DISPATCHER_SERVLET_NAME = "dispatcherServlet";

    private WebServer webServer;
    private shared bool terminated;

    /// A context with a new bean factory.
    this()
    {
        setWebApplicationType("SERVLET");
    }

    /// Refresh; on failure, stop the web server that was created.
    override void refresh()
    {
        try
            super.refresh();
        catch (Exception failure)
        {
            if (webServer !is null)
            {
                try
                    webServer.destroy();
                catch (Exception stopFailure)
                {
                }
            }
            markTerminated();
            throw failure;
        }
    }

    protected override void onRefresh()
    {
        super.onRefresh();
        try
            createWebServer();
        catch (Exception failure)
            throw new ApplicationContextException("Unable to start web server", failure);
    }

    protected override void finishRefresh()
    {
        super.finishRefresh();
        webServer.start();
    }

    // Boot's WebServerGracefulShutdownLifecycle drains the server before the beans are destroyed, then
    // WebServerStartStopLifecycle stops it.
    protected override void doClose()
    {
        if (webServer !is null)
            webServer.shutDownGracefully(new IgnoreResult);
        super.doClose();
        if (webServer !is null)
            webServer.destroy();
        markTerminated();
    }

    /// The embedded web server, or `null` before refresh.
    WebServer getWebServer() pure nothrow @nogc
    {
        return webServer;
    }

    /// Flint addition (`MainThreadHost`): serve requests on the calling thread until the web server stops, when the
    /// server hosts on the main thread (`server.flint.main-thread`); otherwise return at once.
    void hostOnMainThread()
    {
        if (auto hosted = cast(HostedWebServer) webServer)
            hosted.host();
    }

    /// Whether the context has been closed, or failed to start.
    bool isTerminated()
    {
        import core.atomic : atomicLoad;

        return atomicLoad(terminated);
    }

    /// Block until the context is closed.
    void awaitTermination()
    {
        import core.atomic : atomicLoad;
        import core.thread.osthread : Thread;
        import core.time : msecs;

        while (!atomicLoad(terminated))
            Thread.sleep(200.msecs);
    }

    /// The single `ServletWebServerFactory` bean.
    protected ServletWebServerFactory getWebServerFactory()
    {
        import flint.engine.aot.name : typeNameOf;
        import std.array : join;

        auto names = getBeanFactory().getBeanNamesForTypeErased(typeNameOf!ServletWebServerFactory);
        if (names.length == 0)
            throw new ApplicationContextException(
                    "Unable to start ServletWebServerApplicationContext due to "
                    ~ "missing ServletWebServerFactory bean");
        if (names.length > 1)
            throw new ApplicationContextException("Unable to start ServletWebServerApplicationContext due to "
                    ~ "multiple ServletWebServerFactory beans : " ~ names.join(","));
        return cast(ServletWebServerFactory) getBeanFactory().getBean(names[0]);
    }

    private void createWebServer()
    {
        import flint.engine.aot.name : typeNameOf;

        if (webServer !is null)
            return;
        auto factory = getWebServerFactory();
        webServer = factory.getWebServer(new ServletContextInitializerBeans(this).get());
    }

    private void markTerminated() nothrow @nogc
    {
        import core.atomic : atomicStore;

        atomicStore(terminated, true);
    }
}

/// The context's `ServletContextInitializer` beans, with its plain `Servlet` and `Filter` beans adapted to
/// registrations under their bean names (unless a registration bean already covers them), sorted by order.
final class ServletContextInitializerBeans
{
    private ServletContextInitializer[] initializers;

    /// The initializers of `context`.
    this(ServletWebServerApplicationContext context)
    {
        import flint.boot.web.server.servlet : AbstractFilterRegistrationBean,
            DelegatingFilterProxyRegistrationBean, FilterRegistrationBean, ServletRegistrationBean;
        import flint.engine.aot.name : typeNameOf;
        import flint.jakarta.servlet : Filter, Servlet;
        import std.algorithm.searching : canFind;

        auto factory = context.getBeanFactory();
        Object[] seen;
        // Beans a DelegatingFilterProxyRegistrationBean registers, by name, so they are not created here.
        string[] seenNames;
        foreach (name; factory.getBeanNamesForTypeErased(typeNameOf!ServletContextInitializer))
        {
            auto initializer = cast(ServletContextInitializer) factory.getBean(name);
            initializers ~= initializer;
            if (auto servlet = cast(ServletRegistrationBean) initializer)
                seen ~= cast(Object) servlet.getServlet();
            else if (auto proxy = cast(DelegatingFilterProxyRegistrationBean) initializer)
                seenNames ~= proxy.getTargetBeanName();
            else if (auto filter = cast(AbstractFilterRegistrationBean) initializer)
                seen ~= cast(Object) filter.getFilter();
        }
        string[] servletNames;
        foreach (name; factory.getBeanNamesForTypeErased(typeNameOf!Servlet))
        {
            if (!seen.canFind!((a, b) => a is b)(factory.getBean(name)))
                servletNames ~= name;
        }
        foreach (name; servletNames)
        {
            // Boot's ServletRegistrationBeanAdapter: a single servlet (or the dispatcher) maps at "/".
            const url = servletNames.length == 1
                || name == ServletWebServerApplicationContext.DISPATCHER_SERVLET_NAME ? "/" : "/" ~ name ~ "/";
            auto bean = factory.getBean(name);
            auto registration = new ServletRegistrationBean(cast(Servlet) bean, url);
            registration.setName(name);
            registration.setOrder(orderOf(bean));
            initializers ~= registration;
        }
        foreach (name; factory.getBeanNamesForTypeErased(typeNameOf!Filter))
        {
            if (seenNames.canFind(name))
                continue;
            auto bean = factory.getBean(name);
            if (seen.canFind!((a, b) => a is b)(bean))
                continue;
            auto registration = new FilterRegistrationBean(cast(Filter) bean);
            registration.setName(name);
            registration.setOrder(orderOf(bean));
            initializers ~= registration;
        }
        initializers = sortedByOrder(initializers);
    }

    /// The initializers, in order.
    ServletContextInitializer[] get() pure nothrow
    {
        return initializers.dup;
    }

    private static int orderOf(Object bean)
    {
        import flint.core : Ordered;

        if (auto ordered = cast(Ordered) bean)
            return ordered.getOrder();
        return Ordered.LOWEST_PRECEDENCE;
    }

    private static ServletContextInitializer[] sortedByOrder(ServletContextInitializer[] items)
    {
        import std.algorithm.mutation : SwapStrategy;
        import std.algorithm.sorting : sort;

        sort!((a, b) => orderOf(cast(Object) a) < orderOf(cast(Object) b), SwapStrategy.stable)(items);
        return items;
    }
}

// The context only waits for the drain; Boot logs the result, which Flint's servers report through their own logs.
private final class IgnoreResult : GracefulShutdownCallback
{
    void shutdownComplete(GracefulShutdownResult)
    {
    }
}

/// Creates `ServletWebServerApplicationContext`s for `SERVLET` applications.
final class ServletWebServerApplicationContextFactory : ApplicationContextFactory
{
    /// A servlet web server context for `SERVLET`, else `null`.
    ConfigurableApplicationContext create(WebApplicationType webApplicationType)
    {
        return webApplicationType == WebApplicationType.SERVLET ? new ServletWebServerApplicationContext : null;
    }
}

// Boot lists the factory in spring.factories; linking this module registers it.
shared static this()
{
    DefaultApplicationContextFactory.registerWebFactory(WebApplicationType.SERVLET,
            new ServletWebServerApplicationContextFactory);
}
