// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/servlet/ServletWebServerFactory.java
// with core/spring-boot/src/main/java/org/springframework/boot/web/servlet/ServletRegistrationBean.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Flint's servlet engine registers servlets itself, not through
// `ServletContext.addServlet`, so `getWebServer` takes the `ServletRegistrationBean`s rather than
// `ServletContextInitializer`s, and `ServletRegistrationBean` lives here rather than in core (Boot core keeps no
// servlet types in Flint).

/// `org.springframework.boot.web.server.servlet`: servlet web server support.
module flint.boot.web.server.servlet;

import flint.boot.web.server : WebServer;
import flint.jakarta.servlet : Servlet;

@safe:

/// A servlet the embedded web server registers at startup, with its name and URL mappings.
class ServletRegistrationBean
{
    private Servlet servlet;
    private string servletName;
    private string[] urlMappings;

    /// `servlet` under `urlMappings` (all URLs when empty).
    this(Servlet servlet, string[] urlMappings...)
    {
        this.servlet = servlet;
        this.urlMappings = urlMappings.dup;
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
}

/// Creates the embedded servlet web server.
interface ServletWebServerFactory
{
    /// A new, not yet started, `WebServer` that serves `registrations`.
    WebServer getWebServer(ServletRegistrationBean[] registrations...);
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
}
