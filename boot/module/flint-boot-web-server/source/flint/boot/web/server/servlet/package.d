// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/servlet/ServletWebServerFactory.java
// with ConfigurableServletWebServerFactory.java from the same directory, and
// core/spring-boot/src/main/java/org/springframework/boot/web/servlet/ServletContextInitializer.java and
// ServletRegistrationBean.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `ServletContextInitializer` and `ServletRegistrationBean` live here rather than in
// core, which keeps no servlet types in Flint; `ServletRegistrationBean` folds in its
// `DynamicRegistrationBean`/`RegistrationBean` bases; the configurable factory has the settings Flint's engine
// supports.

/// `org.springframework.boot.web.server.servlet`: servlet web server support.
module flint.boot.web.server.servlet;

import flint.boot.web.server : Shutdown, WebServer;
import flint.jakarta.servlet : Servlet, ServletContext;

@safe:

/// Configures a `ServletContext` when the embedded web server starts: registers servlets and filters.
interface ServletContextInitializer
{
    /// Configure `servletContext`.
    void onStartup(ServletContext servletContext);
}

/// Registers a servlet with the `ServletContext` under its name and URL mappings (`/*` when none are given).
class ServletRegistrationBean : ServletContextInitializer
{
    private static immutable string[] DEFAULT_MAPPINGS = ["/*"];

    private Servlet servlet;
    private string servletName;
    private string[] urlMappings;
    private int loadOnStartup = -1;

    /// `servlet` under `urlMappings`.
    this(Servlet servlet, string[] urlMappings...)
    {
        this.servlet = servlet;
        this.urlMappings = urlMappings.dup;
    }

    /// Register the servlet; a servlet already registered under the name is left alone, as Boot does.
    void onStartup(ServletContext servletContext)
    {
        auto registration = servletContext.addServlet(getServletName(), servlet);
        if (registration is null)
            return;
        registration.addMapping(urlMappings.length ? urlMappings : DEFAULT_MAPPINGS.dup);
        registration.setLoadOnStartup(loadOnStartup);
    }

    /// The servlet.
    Servlet getServlet() pure nothrow @nogc
    {
        return servlet;
    }

    /// The servlet's name; by default, its class's simple name with a lower-case first letter.
    string getServletName()
    {
        import std.string : lastIndexOf;
        import std.uni : toLower;

        if (servletName.length)
            return servletName;
        const type = typeid(cast(Object) servlet).name;
        const simple = type[type.lastIndexOf('.') + 1 .. $];
        return simple.length ? simple[0 .. 1].toLower ~ simple[1 .. $] : simple;
    }

    /// Set the servlet's name.
    void setName(string name) pure nothrow @nogc
    {
        this.servletName = name;
    }

    /// The URL mappings.
    string[] getUrlMappings() const pure nothrow
    {
        return urlMappings.dup;
    }

    /// Set the URL mappings.
    void setUrlMappings(string[] urlMappings) pure nothrow
    {
        this.urlMappings = urlMappings.dup;
    }

    /// The `loadOnStartup` priority; -1 loads on first request.
    int getLoadOnStartup() const pure nothrow @nogc
    {
        return loadOnStartup;
    }

    /// Set the `loadOnStartup` priority.
    void setLoadOnStartup(int loadOnStartup) pure nothrow @nogc
    {
        this.loadOnStartup = loadOnStartup;
    }
}

/// Creates the embedded servlet web server.
interface ServletWebServerFactory
{
    /// A new, not yet started, `WebServer`, whose `ServletContext` each of `initializers` configures.
    WebServer getWebServer(ServletContextInitializer[] initializers...);
}

/// A `ServletWebServerFactory` whose listener and context settings can be changed (Boot's
/// `ConfigurableServletWebServerFactory` with `ConfigurableWebServerFactory`).
interface ConfigurableServletWebServerFactory : ServletWebServerFactory
{
    /// Set the port; 0 picks a free port.
    void setPort(int port);
    /// Set the address to bind to.
    void setAddress(string address);
    /// Set the context path: empty, or starting and not ending with `/`.
    void setContextPath(string contextPath);
    /// Set the path that errors are forwarded to.
    void setErrorPath(string errorPath);
    /// Set how the server shuts down.
    void setShutdown(Shutdown shutdown);
}
