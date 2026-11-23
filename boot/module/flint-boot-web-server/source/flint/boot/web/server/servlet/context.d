// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/servlet/context/ServletWebServerApplicationContext.java
// with ServletWebServerApplicationContextFactory.java from the same directory.
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
    KeepAliveApplicationContext, WebApplicationType;
import flint.boot.web.server : WebServer;
import flint.boot.web.server.servlet : ServletRegistrationBean, ServletWebServerFactory;
import flint.context : ApplicationContextException, ConfigurableApplicationContext;
import flint.context.support : GenericApplicationContext;

@safe:

/// An application context that creates, starts and stops an embedded servlet web server: the single
/// `ServletWebServerFactory` bean serves every `ServletRegistrationBean` bean.
class ServletWebServerApplicationContext : GenericApplicationContext, KeepAliveApplicationContext
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

    protected override void doClose()
    {
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

    /// Block until the context is closed.
    void awaitTermination()
    {
        import core.atomic : atomicLoad;
        import core.thread : Thread;
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
        ServletRegistrationBean[] registrations;
        foreach (name; getBeanFactory().getBeanNamesForTypeErased(typeNameOf!ServletRegistrationBean))
            registrations ~= cast(ServletRegistrationBean) getBeanFactory().getBean(name);
        webServer = factory.getWebServer(registrations);
    }

    private void markTerminated() nothrow @nogc
    {
        import core.atomic : atomicStore;

        atomicStore(terminated, true);
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
