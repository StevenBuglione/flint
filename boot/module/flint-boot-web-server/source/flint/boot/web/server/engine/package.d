// Flint's embedded servlet web server for Boot: the counterpart of spring-boot v4.2.0's module/spring-boot-tomcat
// (TomcatWebServer and TomcatServletWebServerFactory), over flint.engine.servlet's ServletEngine.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: clean-room over the Boot types it implements; Tomcat's connector, valves and
// session settings have no counterpart in the engine.

/// Flint's embedded servlet web server: `FlintWebServer` and `FlintServletWebServerFactory`.
module flint.boot.web.server.engine;

import flint.boot.web.server : PortInUseException, WebServer, WebServerException;
import flint.boot.web.server.servlet : ConfigurableServletWebServerFactory, ServletRegistrationBean;
import flint.engine.servlet : ServletEngine, ServletEngineException, ServletEngineOptions;

@safe:

/// A `WebServer` over a `ServletEngine`.
final class FlintWebServer : WebServer
{
    private ServletEngine engine;
    private int configuredPort;
    private bool started;

    /// Over `engine`, configured with `configuredPort`.
    this(ServletEngine engine, int configuredPort) pure nothrow @nogc
    {
        this.engine = engine;
        this.configuredPort = configuredPort;
    }

    /// Bind the port and start serving. Throws `PortInUseException` when the port is taken.
    void start()
    {
        if (started)
            return;
        try
            engine.start();
        catch (ServletEngineException failure)
        {
            import std.algorithm.searching : canFind;

            if (failure.msg.canFind("already in use"))
                throw new PortInUseException(configuredPort, failure);
            throw new WebServerException("Unable to start embedded Flint server", failure);
        }
        started = true;
    }

    /// Stop serving.
    void stop()
    {
        if (!started)
            return;
        started = false;
        engine.stop();
    }

    /// The bound port, or -1 before `start`.
    int getPort()
    {
        return engine.getPort();
    }

    /// Stop serving and release the engine.
    void destroy()
    {
        stop();
    }

    /// The engine.
    ServletEngine getEngine() pure nothrow @nogc
    {
        return engine;
    }
}

/// Creates `FlintWebServer`s: Boot's `TomcatServletWebServerFactory` for Flint's engine. Port 8080, all
/// addresses, the root context and `/error` unless configured.
class FlintServletWebServerFactory : ConfigurableServletWebServerFactory
{
    private int port = 8080;
    private string address;
    private string contextPath = "";
    private string errorPath = "/error";

    /// The default factory.
    this() pure nothrow @nogc
    {
    }

    /// A factory listening on `port`.
    this(int port) pure nothrow @nogc
    {
        this.port = port;
    }

    /// A server for `registrations`, configured but not started.
    FlintWebServer getWebServer(ServletRegistrationBean[] registrations...)
    {
        ServletEngineOptions options;
        options.port = cast(ushort) port;
        if (address.length)
            options.address = address;
        options.contextPath = contextPath;
        options.globalErrorPage = errorPath;
        auto engine = new ServletEngine(options);
        foreach (registration; registrations)
        {
            auto mappings = registration.getUrlMappings();
            engine.addServlet(registration.getServletName(), registration.getServlet(),
                    mappings.length ? mappings : ["/"]);
        }
        return new FlintWebServer(engine, port);
    }

    /// The port.
    int getPort() const pure nothrow @nogc
    {
        return port;
    }

    /// Set the port; 0 picks a free port.
    void setPort(int port)
    {
        import flint.java.lang : IllegalArgumentException;

        if (port < 0 || port > ushort.max)
            throw new IllegalArgumentException("Port must be between 0 and 65535");
        this.port = port;
    }

    /// The address, or `null` for all addresses.
    string getAddress() const pure nothrow @nogc
    {
        return address;
    }

    /// Set the address to bind to.
    void setAddress(string address)
    {
        this.address = address;
    }

    /// The context path.
    string getContextPath() const pure nothrow @nogc
    {
        return contextPath;
    }

    /// Set the context path: empty, or starting and not ending with `/`.
    void setContextPath(string contextPath)
    {
        import flint.java.lang : IllegalArgumentException;

        if (contextPath.length && (contextPath[0] != '/' || contextPath[$ - 1] == '/'))
            throw new IllegalArgumentException("ContextPath must start with '/' and not end with '/'");
        this.contextPath = contextPath;
    }

    /// The path errors are forwarded to.
    string getErrorPath() const pure nothrow @nogc
    {
        return errorPath;
    }

    /// Set the path errors are forwarded to.
    void setErrorPath(string errorPath)
    {
        this.errorPath = errorPath;
    }
}
