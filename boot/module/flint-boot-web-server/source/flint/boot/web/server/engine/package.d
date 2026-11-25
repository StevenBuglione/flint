// Flint's embedded servlet web server for Boot: the counterpart of spring-boot v4.2.0's module/spring-boot-tomcat
// (TomcatWebServer and TomcatServletWebServerFactory), over flint.engine.servlet's ServletEngine.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: clean-room over the Boot types it implements; Tomcat's connector, valves and
// session settings have no counterpart in the engine. Flint addition: FlintServletWebServerFactory's fast-path offer
// (setFastOffer, docs/spring/phase1/fast-path.md), set only by Flint AOT's generated customizer.

/// Flint's embedded servlet web server: `FlintWebServer` and `FlintServletWebServerFactory`.
module flint.boot.web.server.engine;

import flint.boot.web.server : GracefulShutdownCallback, GracefulShutdownResult, PortInUseException,
    Shutdown, WebServer, WebServerException;
import flint.boot.web.server.servlet : ConfigurableServletWebServerFactory, ServletContextInitializer;
import flint.engine.servlet : ServletEngine, ServletEngineException, ServletEngineOptions;

@safe:

/// A `WebServer` over a `ServletEngine`.
final class FlintWebServer : WebServer
{
    // Boot's spring.lifecycle.timeout-per-shutdown-phase default.
    private enum long gracePeriodNanos = 30_000_000_000L;

    private ServletEngine engine;
    private int configuredPort;
    private Shutdown shutdown;
    private bool started;

    /// Over `engine`, configured with `configuredPort` and `shutdown`.
    this(ServletEngine engine, int configuredPort, Shutdown shutdown = Shutdown.GRACEFUL) pure nothrow @nogc
    {
        this.engine = engine;
        this.configuredPort = configuredPort;
        this.shutdown = shutdown;
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
                throw new PortInUseException(failure.port, failure);
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

    /// Close the listener, let active requests finish within the grace period, then stop; `IMMEDIATE` when the
    /// server is configured to stop at once. The engine drains on the calling thread, where Tomcat's
    /// `GracefulShutdown` uses its own; the context waits for the result either way.
    void shutDownGracefully(GracefulShutdownCallback callback)
    {
        if (shutdown == Shutdown.IMMEDIATE || !started)
        {
            callback.shutdownComplete(GracefulShutdownResult.IMMEDIATE);
            return;
        }
        started = false;
        const idle = engine.shutDownGracefully(gracePeriodNanos);
        callback.shutdownComplete(idle ? GracefulShutdownResult.IDLE : GracefulShutdownResult.REQUESTS_ACTIVE);
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
    private Shutdown shutdown = Shutdown.GRACEFUL;
    private int threads;
    private int maxHandlers = 200;
    private int maxKeepAliveRequests = 100;
    private FastOffer fastOffer;

    /// The engine's fast-path offer type, named through its options, as the shutdown mode is.
    alias FastOffer = typeof(ServletEngineOptions.init.fastOffer);

    /// The default factory.
    this() pure nothrow @nogc
    {
    }

    /// A factory listening on `port`.
    this(int port) pure nothrow @nogc
    {
        this.port = port;
    }

    /// A server whose `ServletContext` each of `initializers` configures, not yet started.
    FlintWebServer getWebServer(ServletContextInitializer[] initializers...)
    {
        // The engine's shutdown mode, named through its options (flint:engine-web is the engine's dependency).
        alias ShutdownMode = typeof(ServletEngineOptions.init.shutdown);

        ServletEngineOptions options;
        options.port = cast(ushort) port;
        if (address.length)
            options.address = address;
        options.contextPath = contextPath;
        options.globalErrorPage = errorPath;
        options.shutdown = shutdown == Shutdown.GRACEFUL ? ShutdownMode.graceful : ShutdownMode.immediate;
        options.cores = threads;
        options.maxHandlers = cast(uint) maxHandlers; // setMaxHandlers keeps it non-negative
        // Tomcat's 0 disables keep-alive, as 1 does; the engine's 0 or less is unlimited, Tomcat's -1.
        options.maxKeepAliveRequests = maxKeepAliveRequests == 0 ? 1 : maxKeepAliveRequests;
        if (fastOffer !is null)
            options.fastOffer = fastOffer;
        auto engine = new ServletEngine(options);
        foreach (initializer; initializers)
            initializer.onStartup(engine.getServletContext());
        return new FlintWebServer(engine, port, shutdown);
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

    /// How the server shuts down.
    Shutdown getShutdown() const pure nothrow @nogc
    {
        return shutdown;
    }

    /// Set how the server shuts down: `GRACEFUL` (Boot's default) or `IMMEDIATE`.
    void setShutdown(Shutdown shutdown)
    {
        this.shutdown = shutdown;
    }

    /// The reactor threads serving requests; 0, the default, is every CPU the process may run on, up to 16.
    int getThreads() const pure nothrow @nogc
    {
        return threads;
    }

    /// Set the reactor threads serving requests (`server.flint.threads`); 0 is every CPU, up to 16.
    void setThreads(int threads)
    {
        import flint.java.lang : IllegalArgumentException;

        if (threads < 0 || threads > 16)
            throw new IllegalArgumentException("Threads must be between 0 and 16");
        this.threads = threads;
    }

    /// The requests handled at once across the reactor threads; 200, the default, is Tomcat's `threads.max`.
    int getMaxHandlers() const pure nothrow @nogc
    {
        return maxHandlers;
    }

    /// Set the requests handled at once across the reactor threads (`server.flint.max-handlers`), as Tomcat's
    /// `setMaxThreads`; requests past it wait on their connections. 0 runs one handler per connection slot.
    void setMaxHandlers(int maxHandlers)
    {
        import flint.java.lang : IllegalArgumentException;

        if (maxHandlers < 0)
            throw new IllegalArgumentException("Max handlers must not be negative");
        this.maxHandlers = maxHandlers;
    }

    /// The maximum number of requests a connection serves before it closes, as Tomcat's `maxKeepAliveRequests`:
    /// 0 or 1 disables keep-alive, -1 allows any number (`server.tomcat.max-keep-alive-requests`, default 100).
    int getMaxKeepAliveRequests() const pure nothrow @nogc
    {
        return maxKeepAliveRequests;
    }

    /// Set the maximum number of requests a connection serves before it closes (Tomcat's `setMaxKeepAliveRequests`).
    void setMaxKeepAliveRequests(int maxKeepAliveRequests) pure nothrow @nogc
    {
        this.maxKeepAliveRequests = maxKeepAliveRequests;
    }

    /// Flint addition: the per-endpoint fast path's offer (docs/spring/phase1/fast-path.md), or null for none.
    FastOffer getFastOffer() const pure nothrow @nogc
    {
        return fastOffer;
    }

    /++
    Flint addition: the per-endpoint fast path's offer, `flint.engine.servlet.fast.serveFast`. Only the
    `WebServerFactoryCustomizer` Flint AOT generates when an endpoint qualifies calls it, so a server without one
    links none of the fast path; there is no configuration property. Null keeps every request generic.
    +/
    void setFastOffer(FastOffer fastOffer) pure nothrow @nogc
    {
        this.fastOffer = fastOffer;
    }
}
