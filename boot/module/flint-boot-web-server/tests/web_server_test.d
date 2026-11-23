/// Flint tests: Flint's servlet web server factory, `server.*` customisation, the servlet web server context and
/// the port-in-use analysis. Starting a server needs the pinned llhttp (FlintNativeLlhttp), as engine-servlet's
/// own socket tests do.
module web_server_test;

import flint.boot : DefaultApplicationContextFactory, WebApplicationType;
import flint.boot.web.server : PortInUseException, PortInUseFailureAnalyzer, Shutdown;
import flint.boot.web.server.autoconfigure : ServerProperties, ServletWebServerFactoryCustomizer;
import flint.boot.web.server.engine : FlintServletWebServerFactory;
import flint.boot.web.server.servlet.context : ServletWebServerApplicationContext;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Optional;

@safe:

@("the factory defaults to port 8080, every address, the root context and /error") unittest
{
    auto factory = new FlintServletWebServerFactory;
    assert(factory.getPort() == 8080);
    assert(factory.getAddress() is null);
    assert(factory.getContextPath() == "");
    assert(factory.getErrorPath() == "/error");
}

@("a context path must start with / and not end with /; a port must fit") unittest
{
    auto factory = new FlintServletWebServerFactory;
    factory.setContextPath("/api");
    assert(factory.getContextPath() == "/api");
    foreach (bad; ["api", "/api/"])
    {
        bool thrown;
        try
            factory.setContextPath(bad);
        catch (IllegalArgumentException)
            thrown = true;
        assert(thrown, bad);
    }
    bool thrown;
    try
        factory.setPort(70_000);
    catch (IllegalArgumentException)
        thrown = true;
    assert(thrown);
}

@("ServletWebServerFactoryCustomizer applies server.port, server.address and server.servlet.context-path") unittest
{
    auto properties = new ServerProperties;
    auto factory = new FlintServletWebServerFactory;
    new ServletWebServerFactoryCustomizer(properties).customize(factory);
    assert(factory.getPort() == 8080 && factory.getAddress() is null && factory.getContextPath() == "");
    properties.setPort(Optional!int.of(9090));
    properties.setAddress("127.0.0.1");
    properties.getServlet().setContextPath("/app");
    properties.setShutdown(Shutdown.IMMEDIATE);
    assert(factory.getShutdown() == Shutdown.GRACEFUL);
    new ServletWebServerFactoryCustomizer(properties).customize(factory);
    assert(factory.getShutdown() == Shutdown.IMMEDIATE);
    assert(factory.getPort() == 9090);
    assert(factory.getAddress() == "127.0.0.1");
    assert(factory.getContextPath() == "/app");
}

@("server.servlet.context-path is cleaned as Boot cleans it: trimmed, without a trailing slash") unittest
{
    auto servlet = new ServerProperties().getServlet();
    servlet.setContextPath("/petclinic/");
    assert(servlet.getContextPath() == "/petclinic");
    servlet.setContextPath(" /api ");
    assert(servlet.getContextPath() == "/api");
    servlet.setContextPath("/");
    assert(servlet.getContextPath() == "");
    servlet.setContextPath(null);
    assert(servlet.getContextPath() is null);
}

@("linking the module registers the servlet context factory, so SERVLET is deduced") unittest
{
    assert(DefaultApplicationContextFactory.deduceWebApplicationType() == WebApplicationType.SERVLET);
    const context = new DefaultApplicationContextFactory().create(WebApplicationType.SERVLET);
    assert(cast(const ServletWebServerApplicationContext) context !is null);
    assert(new DefaultApplicationContextFactory().create(WebApplicationType.NONE) !is null);
}

@("PortInUseFailureAnalyzer reports Boot's description and action") unittest
{
    import flint.boot.diagnostics : FailureAnalyzer;

    FailureAnalyzer analyzer = new PortInUseFailureAnalyzer;
    auto analysis = analyzer.analyze(new PortInUseException(8080));
    assert(analysis !is null);
    assert(analysis.getDescription() == "Web server failed to start. Port 8080 was already in use.");
    assert(analysis.getAction() == "Identify and stop the process that's listening on port 8080 or configure this "
            ~ "application to listen on another port.");
}

private final class NamedFilter : imported!"flint.web.filter".OncePerRequestFilter, imported!"flint.core".Ordered
{
    private int order;

    this(int order)
    {
        this.order = order;
    }

    protected override void doFilterInternal(imported!"flint.jakarta.servlet.http".HttpServletRequest request,
            imported!"flint.jakarta.servlet.http".HttpServletResponse response,
            imported!"flint.jakarta.servlet".FilterChain chain)
    {
        chain.doFilter(request, response);
    }

    int getOrder()
    {
        return order;
    }
}

@("ServletContextInitializerBeans: Filter beans are adapted under their names, in order, unless registered") unittest
{
    import flint.boot.web.server.servlet : AbstractFilterRegistrationBean, FilterRegistrationBean;
    import flint.boot.web.server.servlet.context : ServletContextInitializerBeans;
    import flint.jakarta.servlet : DispatcherType;

    auto context = new ServletWebServerApplicationContext;
    auto registered = new NamedFilter(0);
    context.getBeanFactory().registerSingleton("second", new NamedFilter(2));
    context.getBeanFactory().registerSingleton("first", new NamedFilter(1));
    context.getBeanFactory().registerSingleton("registered", registered);
    auto registration = new FilterRegistrationBean(registered);
    registration.setName("explicit");
    registration.setOrder(-5);
    context.getBeanFactory().registerSingleton("registration", registration);
    string[] names;
    foreach (initializer; new ServletContextInitializerBeans(context).get())
        names ~= (cast(AbstractFilterRegistrationBean) initializer).getFilterName();
    assert(names == ["explicit", "first", "second"], imported!"std.conv".to!string(names));
    assert(registration.getDispatcherTypes() == [DispatcherType.REQUEST]);
}

version (FlintNativeLlhttp)
{
    import flint.jakarta.servlet.http : HttpServlet;

    private final class EmptyServlet : HttpServlet
    {
    }

    // Answers GET with "ok".
    private final class OkServlet : HttpServlet
    {
        protected override void doGet(imported!"flint.jakarta.servlet.http".HttpServletRequest,
                imported!"flint.jakarta.servlet.http".HttpServletResponse response)
        {
            response.setContentType("text/plain");
            response.getWriter().write("ok");
        }
    }

    private string get(int port, string path) @trusted
    {
        // SAFETY: test-only; std.socket's blocking calls on a local socket that lives for this call.
        import std.socket : InternetAddress, TcpSocket;
        import std.conv : to;

        auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) port));
        scope (exit)
            socket.close();
        socket.send("GET " ~ path ~ " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
        char[] response;
        char[4096] buffer;
        for (;;)
        {
            const received = socket.receive(buffer[]);
            if (received <= 0)
                break;
            response ~= buffer[0 .. received];
        }
        return response.idup;
    }

    private final class Recorder : imported!"flint.boot.web.server".GracefulShutdownCallback
    {
        imported!"flint.boot.web.server".GracefulShutdownResult result;
        bool called;

        void shutdownComplete(imported!"flint.boot.web.server".GracefulShutdownResult result)
        {
            this.result = result;
            called = true;
        }
    }

    @("a ServletRegistrationBean registers through the ServletContext; an idle server shuts down IDLE") unittest
    {
        import flint.boot.web.server : GracefulShutdownResult;
        import flint.boot.web.server.servlet : ServletRegistrationBean;
        import std.algorithm.searching : canFind, endsWith;

        auto registration = new ServletRegistrationBean(new OkServlet, "/");
        registration.setName("ok");
        auto server = new FlintServletWebServerFactory(0).getWebServer(registration);
        server.start();
        scope (exit)
            server.destroy();
        const response = get(server.getPort(), "/anything");
        assert(response.canFind("200") && response.endsWith("ok"), response);
        auto recorder = new Recorder;
        server.shutDownGracefully(recorder);
        assert(recorder.called && recorder.result == GracefulShutdownResult.IDLE);
    }

    @("an IMMEDIATE server reports IMMEDIATE") unittest
    {
        import flint.boot.web.server : GracefulShutdownResult;
        import flint.boot.web.server.servlet : ServletRegistrationBean;

        auto factory = new FlintServletWebServerFactory(0);
        factory.setShutdown(Shutdown.IMMEDIATE);
        auto server = factory.getWebServer(new ServletRegistrationBean(new EmptyServlet, "/"));
        server.start();
        scope (exit)
            server.destroy();
        auto recorder = new Recorder;
        server.shutDownGracefully(recorder);
        assert(recorder.result == GracefulShutdownResult.IMMEDIATE);
    }

    @("a second server on a taken port fails with PortInUseException") unittest
    {
        import flint.boot.web.server.servlet : ServletRegistrationBean;

        auto factory = new FlintServletWebServerFactory(0);
        auto first = factory.getWebServer(new ServletRegistrationBean(new EmptyServlet, "/"));
        first.start();
        scope (exit)
            first.stop();
        assert(first.getPort() > 0);
        auto second = new FlintServletWebServerFactory(first.getPort()).getWebServer(
                new ServletRegistrationBean(new EmptyServlet, "/"));
        bool thrown;
        try
            second.start();
        catch (PortInUseException e)
            thrown = e.getPort() == first.getPort();
        assert(thrown);
    }

    // Adds `X-Filtered: yes` before the chain.
    private final class HeaderFilter : imported!"flint.web.filter".OncePerRequestFilter
    {
        protected override void doFilterInternal(imported!"flint.jakarta.servlet.http".HttpServletRequest request,
                imported!"flint.jakarta.servlet.http".HttpServletResponse response,
                imported!"flint.jakarta.servlet".FilterChain chain)
        {
            response.setHeader("X-Filtered", "yes");
            chain.doFilter(request, response);
        }
    }

    @("a FilterRegistrationBean's filter runs before the servlet, at its URL pattern") unittest
    {
        import flint.boot.web.server.servlet : FilterRegistrationBean, ServletRegistrationBean;
        import std.algorithm.searching : canFind;

        auto filter = new FilterRegistrationBean(new HeaderFilter);
        filter.setUrlPatterns("/filtered/*");
        auto server = new FlintServletWebServerFactory(0).getWebServer(new ServletRegistrationBean(new OkServlet,
                "/"), filter);
        server.start();
        scope (exit)
            server.destroy();
        assert(get(server.getPort(), "/filtered/x").canFind("X-Filtered: yes"));
        assert(!get(server.getPort(), "/other").canFind("X-Filtered"));
    }
}
