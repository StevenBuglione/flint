// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/servlet/ServletWebServerFactory.java
// with ConfigurableServletWebServerFactory.java from the same directory, and
// core/spring-boot/src/main/java/org/springframework/boot/web/servlet/ServletContextInitializer.java,
// RegistrationBean.java, ServletRegistrationBean.java, AbstractFilterRegistrationBean.java and FilterRegistrationBean.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `ServletContextInitializer` and `ServletRegistrationBean` live here rather than in
// core, which keeps no servlet types in Flint; `ServletRegistrationBean` folds in its
// `DynamicRegistrationBean` base into `RegistrationBean`; the configurable factory has the settings Flint's engine
// supports.

/// `org.springframework.boot.web.server.servlet`: servlet web server support.
module flint.boot.web.server.servlet;

import flint.boot.web.server : Shutdown, WebServer;
import flint.core : Ordered;
import flint.jakarta.servlet : DispatcherType, Filter, Servlet, ServletContext;

@safe:

/// Configures a `ServletContext` when the embedded web server starts: registers servlets and filters.
interface ServletContextInitializer
{
    /// Configure `servletContext`.
    void onStartup(ServletContext servletContext);
}

/// A `ServletContextInitializer` that registers one servlet or filter, with an order and an enabled switch.
abstract class RegistrationBean : ServletContextInitializer, Ordered
{
    private int order = Ordered.LOWEST_PRECEDENCE;
    private bool enabled = true;

    /// Register, unless disabled.
    final void onStartup(ServletContext servletContext)
    {
        if (enabled)
            register(servletContext);
    }

    /// Register with `servletContext`.
    protected abstract void register(ServletContext servletContext);

    /// The order among initializers.
    int getOrder()
    {
        return order;
    }

    /// Set the order.
    void setOrder(int order) pure nothrow @nogc
    {
        this.order = order;
    }

    /// Whether the registration is enabled.
    bool isEnabled() const pure nothrow @nogc
    {
        return enabled;
    }

    /// Enable or disable the registration.
    void setEnabled(bool enabled) pure nothrow @nogc
    {
        this.enabled = enabled;
    }

    // Boot's getOrDeduceName: the explicit name, else the class's simple name with a lower-case first letter.
    protected static string deduceName(string name, Object value)
    {
        import std.string : lastIndexOf;
        import std.uni : toLower;

        if (name.length)
            return name;
        const type = typeid(value).name;
        const simple = type[type.lastIndexOf('.') + 1 .. $];
        return simple.length ? simple[0 .. 1].toLower ~ simple[1 .. $] : simple;
    }
}

/// Registers a servlet with the `ServletContext` under its name and URL mappings (`/*` when none are given).
class ServletRegistrationBean : RegistrationBean
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
    protected override void register(ServletContext servletContext)
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
        return deduceName(servletName, cast(Object) servlet);
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

/// Registers a filter: its URL patterns or servlet names (`/*` when neither is given), dispatcher types (`REQUEST`
/// by default) and whether it matches after the filters declared in the deployment.
abstract class AbstractFilterRegistrationBean : RegistrationBean
{
    private static immutable string[] DEFAULT_URL_MAPPINGS = ["/*"];

    private string name;
    private string[] urlPatterns;
    private string[] servletNames;
    private DispatcherType[] dispatcherTypes;
    private bool matchAfter;
    private string[string] initParameters;

    /// The filter to register.
    abstract Filter getFilter();

    /// Set the filter's registered name.
    void setName(string name) pure nothrow @nogc
    {
        this.name = name;
    }

    /// The filter's registered name: the set name, else the filter class's simple name.
    string getFilterName()
    {
        return deduceName(name, cast(Object) getFilter());
    }

    /// Set the URL patterns.
    void setUrlPatterns(string[] urlPatterns...) pure nothrow
    {
        this.urlPatterns = urlPatterns.dup;
    }

    /// Add URL patterns.
    void addUrlPatterns(string[] urlPatterns...) pure nothrow
    {
        this.urlPatterns ~= urlPatterns;
    }

    /// The URL patterns.
    string[] getUrlPatterns() pure nothrow
    {
        return urlPatterns.dup;
    }

    /// Set the servlet names the filter applies to.
    void setServletNames(string[] servletNames...) pure nothrow
    {
        this.servletNames = servletNames.dup;
    }

    /// The servlet names.
    string[] getServletNames() pure nothrow
    {
        return servletNames.dup;
    }

    /// Set the dispatcher types; `REQUEST` when none are set.
    void setDispatcherTypes(DispatcherType[] dispatcherTypes...) pure nothrow
    {
        this.dispatcherTypes = dispatcherTypes.dup;
    }

    /// The dispatcher types.
    DispatcherType[] getDispatcherTypes() pure nothrow
    {
        return dispatcherTypes.length ? dispatcherTypes.dup : [DispatcherType.REQUEST];
    }

    /// Set whether the filter matches after those declared in the deployment.
    void setMatchAfter(bool matchAfter) pure nothrow @nogc
    {
        this.matchAfter = matchAfter;
    }

    /// Whether the filter matches after those declared in the deployment.
    bool isMatchAfter() const pure nothrow @nogc
    {
        return matchAfter;
    }

    /// Add an init parameter.
    void addInitParameter(string name, string value) pure nothrow
    {
        initParameters[name] = value;
    }

    /// Register the filter; a filter already registered under the name is left alone, as Boot does.
    protected override void register(ServletContext servletContext)
    {
        auto registration = servletContext.addFilter(getFilterName(), getFilter());
        if (registration is null)
            return;
        foreach (key, value; initParameters)
            registration.setInitParameter(key, value);
        if (servletNames.length == 0 && urlPatterns.length == 0)
        {
            registration.addMappingForUrlPatterns(getDispatcherTypes(), matchAfter, DEFAULT_URL_MAPPINGS.dup);
            return;
        }
        if (servletNames.length)
            registration.addMappingForServletNames(getDispatcherTypes(), matchAfter, servletNames);
        if (urlPatterns.length)
            registration.addMappingForUrlPatterns(getDispatcherTypes(), matchAfter, urlPatterns);
    }
}

/// Registers a filter instance.
class FilterRegistrationBean : AbstractFilterRegistrationBean
{
    private Filter filter;

    /// For `filter`, set later or now; `servletRegistrationBeans` restrict it to those servlets.
    this(Filter filter = null, ServletRegistrationBean[] servletRegistrationBeans...)
    {
        this.filter = filter;
        foreach (registration; servletRegistrationBeans)
            addServletNames(registration.getServletName());
    }

    /// The filter.
    override Filter getFilter()
    {
        return filter;
    }

    /// Set the filter.
    void setFilter(Filter filter) pure nothrow @nogc
    {
        this.filter = filter;
    }

    private void addServletNames(string name)
    {
        setServletNames(getServletNames() ~ name);
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
