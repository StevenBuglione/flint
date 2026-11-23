/// Flint test fixture for the ported spring-boot v4.2.0 web server and servlet registration tests: the Mockito
/// mocks of `ServletContext`, `ServletRegistration.Dynamic` and `FilterRegistration.Dynamic` as recording fakes,
/// and Boot's `MockServletWebServerFactory` (spring-boot-web-server's testFixtures) over them.
module web_server_test_support;

import flint.boot.web.server : GracefulShutdownCallback, GracefulShutdownResult, Shutdown, WebServer;
import flint.boot.web.server.servlet : ConfigurableServletWebServerFactory, ServletContextInitializer;
import flint.engine.aot.any : Any;
import flint.jakarta.servlet : DispatcherType, Filter, FilterRegistration, Servlet,
    ServletContext, ServletRegistration;

@safe:

/// A recorded `addMappingForUrlPatterns` or `addMappingForServletNames` call.
struct FilterMapping
{
    /// The dispatcher types.
    DispatcherType[] dispatcherTypes;
    /// Whether the mapping matches after the declared ones.
    bool matchAfter;
    /// The URL patterns or servlet names.
    string[] values;
}

/// Records what a registration bean does with a servlet's registration.
final class RecordingServletRegistration : ServletRegistration.Dynamic
{
    /// The servlet's name.
    string name;
    /// The servlet.
    Servlet servlet;
    /// `setAsyncSupported` calls, in order.
    bool[] asyncSupported;
    /// The init parameters set.
    string[string] initParameters;
    /// Each `addMapping` call's patterns.
    string[][] mappings;
    /// `setLoadOnStartup` calls, in order.
    int[] loadOnStartup;

    /// A fake over the given values.
    this(string name, Servlet servlet) pure nothrow @nogc
    {
        this.name = name;
        this.servlet = servlet;
    }

    /// See the interface; recorded.
    string getName()
    {
        return name;
    }

    /// See the interface; recorded.
    string getClassName()
    {
        return typeid(cast(Object) servlet).name;
    }

    /// See the interface; recorded.
    bool setInitParameter(string name, string value)
    {
        if (name in initParameters)
            return false;
        initParameters[name] = value;
        return true;
    }

    /// See the interface; recorded.
    string getInitParameter(string name)
    {
        if (auto value = name in initParameters)
            return *value;
        return null;
    }

    /// See the interface; recorded.
    void setAsyncSupported(bool isAsyncSupported)
    {
        asyncSupported ~= isAsyncSupported;
    }

    /// See the interface; recorded.
    string[] addMapping(string[] urlPatterns...)
    {
        mappings ~= urlPatterns.dup;
        return null;
    }

    /// See the interface; recorded.
    string[] getMappings()
    {
        string[] all;
        foreach (mapping; mappings)
            all ~= mapping;
        return all;
    }

    /// See the interface; recorded.
    string getRunAsRole()
    {
        return null;
    }

    /// See the interface; recorded.
    void setLoadOnStartup(int loadOnStartup)
    {
        this.loadOnStartup ~= loadOnStartup;
    }

    /// See the interface; recorded.
    void setRunAsRole(string)
    {
    }
}

/// Records what a registration bean does with a filter's registration.
final class RecordingFilterRegistration : FilterRegistration.Dynamic
{
    /// The filter's name.
    string name;
    /// The filter.
    Filter filter;
    /// `setAsyncSupported` calls, in order.
    bool[] asyncSupported;
    /// The init parameters set.
    string[string] initParameters;
    /// `addMappingForUrlPatterns` calls.
    FilterMapping[] urlPatternMappings;
    /// `addMappingForServletNames` calls.
    FilterMapping[] servletNameMappings;

    /// A fake over the given values.
    this(string name, Filter filter) pure nothrow @nogc
    {
        this.name = name;
        this.filter = filter;
    }

    /// See the interface; recorded.
    string getName()
    {
        return name;
    }

    /// See the interface; recorded.
    string getClassName()
    {
        return typeid(cast(Object) filter).name;
    }

    /// See the interface; recorded.
    bool setInitParameter(string name, string value)
    {
        if (name in initParameters)
            return false;
        initParameters[name] = value;
        return true;
    }

    /// See the interface; recorded.
    string getInitParameter(string name)
    {
        if (auto value = name in initParameters)
            return *value;
        return null;
    }

    /// See the interface; recorded.
    void setAsyncSupported(bool isAsyncSupported)
    {
        asyncSupported ~= isAsyncSupported;
    }

    /// See the interface; recorded.
    void addMappingForServletNames(DispatcherType[] dispatcherTypes, bool isMatchAfter, string[] servletNames...)
    {
        servletNameMappings ~= FilterMapping(dispatcherTypes.dup, isMatchAfter, servletNames.dup);
    }

    /// See the interface; recorded.
    string[] getServletNameMappings()
    {
        string[] all;
        foreach (mapping; servletNameMappings)
            all ~= mapping.values;
        return all;
    }

    /// See the interface; recorded.
    void addMappingForUrlPatterns(DispatcherType[] dispatcherTypes, bool isMatchAfter, string[] urlPatterns...)
    {
        urlPatternMappings ~= FilterMapping(dispatcherTypes.dup, isMatchAfter, urlPatterns.dup);
    }

    /// See the interface; recorded.
    string[] getUrlPatternMappings()
    {
        string[] all;
        foreach (mapping; urlPatternMappings)
            all ~= mapping.values;
        return all;
    }
}

/// A `ServletContext` that records the servlets and filters added to it. With `refuseRegistrations`, `addServlet`
/// and `addFilter` return null, as a container does for a name already registered.
final class RecordingServletContext : ServletContext
{
    /// The servlet registrations, in order.
    RecordingServletRegistration[] servlets;
    /// The filter registrations, in order.
    RecordingFilterRegistration[] filters;
    /// Every `addServlet` and `addFilter` call's name, in order.
    string[] calls;
    /// Whether registrations are refused.
    bool refuseRegistrations;
    private Any[string] attributes;

    /// See the interface; recorded.
    string getContextPath()
    {
        return "";
    }

    /// See the interface; recorded.
    Any getAttribute(string name)
    {
        if (auto value = name in attributes)
            return *value;
        return Any.init;
    }

    /// See the interface; recorded.
    void setAttribute(string name, Any object)
    {
        attributes[name] = object;
    }

    /// See the interface; recorded.
    string getServerInfo()
    {
        return "recording";
    }

    /// See the interface; recorded.
    string getMimeType(string)
    {
        return null;
    }

    /// See the interface; recorded.
    int getMajorVersion()
    {
        return 6;
    }

    /// See the interface; recorded.
    int getMinorVersion()
    {
        return 1;
    }

    /// See the interface; recorded.
    ServletRegistration.Dynamic addServlet(string servletName, Servlet servlet)
    {
        calls ~= servletName;
        if (refuseRegistrations)
            return null;
        auto registration = new RecordingServletRegistration(servletName, servlet);
        servlets ~= registration;
        return registration;
    }

    /// See the interface; recorded.
    FilterRegistration.Dynamic addFilter(string filterName, Filter filter)
    {
        calls ~= filterName;
        if (refuseRegistrations)
            return null;
        auto registration = new RecordingFilterRegistration(filterName, filter);
        filters ~= registration;
        return registration;
    }
}

/// Boot's `MockServletWebServerFactory`'s server: counts its lifecycle calls.
final class MockWebServer : WebServer
{
    /// Calls so far.
    int starts, stops, destroys;
    /// The configured port.
    int port;
    /// Thrown by the next `stop`, then cleared.
    Exception failOnStop;
    /// Thrown by the next `destroy`, then cleared.
    Exception failOnDestroy;

    /// A fake over the given values.
    this(int port) pure nothrow @nogc
    {
        this.port = port;
    }

    /// See the interface; recorded.
    void start()
    {
        starts++;
    }

    /// See the interface; recorded.
    void stop()
    {
        stops++;
        if (auto failure = failOnStop)
        {
            failOnStop = null;
            throw failure;
        }
    }

    /// See the interface; recorded.
    int getPort()
    {
        return port;
    }

    /// See the interface; recorded.
    void destroy()
    {
        destroys++;
        if (auto failure = failOnDestroy)
        {
            failOnDestroy = null;
            throw failure;
        }
        stop();
    }

    /// See the interface; recorded.
    void shutDownGracefully(GracefulShutdownCallback callback)
    {
        callback.shutdownComplete(GracefulShutdownResult.IMMEDIATE);
    }
}

/// Boot's `MockServletWebServerFactory`: a recording servlet context, each initializer run against it.
final class MockServletWebServerFactory : ConfigurableServletWebServerFactory
{
    /// The context the initializers configured.
    RecordingServletContext servletContext;
    /// The last server created.
    MockWebServer webServer;
    /// The configured settings.
    int port = 8080;
    /// ditto
    string address;
    /// ditto
    string contextPath;
    /// ditto
    string errorPath;
    /// ditto
    Shutdown shutdown = Shutdown.GRACEFUL;

    /// See the interface; recorded.
    MockWebServer getWebServer(ServletContextInitializer[] initializers...)
    {
        servletContext = new RecordingServletContext;
        foreach (initializer; initializers)
            initializer.onStartup(servletContext);
        webServer = new MockWebServer(port);
        return webServer;
    }

    /// See the interface; recorded.
    void setPort(int port)
    {
        this.port = port;
    }

    /// See the interface; recorded.
    void setAddress(string address)
    {
        this.address = address;
    }

    /// See the interface; recorded.
    void setContextPath(string contextPath)
    {
        this.contextPath = contextPath;
    }

    /// See the interface; recorded.
    void setErrorPath(string errorPath)
    {
        this.errorPath = errorPath;
    }

    /// See the interface; recorded.
    void setShutdown(Shutdown shutdown)
    {
        this.shutdown = shutdown;
    }
}
