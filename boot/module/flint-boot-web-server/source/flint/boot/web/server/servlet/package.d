// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/servlet/ServletWebServerFactory.java
// with ConfigurableServletWebServerFactory.java from the same directory, and
// core/spring-boot/src/main/java/org/springframework/boot/web/servlet/ServletContextInitializer.java,
// RegistrationBean.java, ServletRegistrationBean.java, AbstractFilterRegistrationBean.java, FilterRegistrationBean.java and
// DelegatingFilterProxyRegistrationBean.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `ServletContextInitializer` and `ServletRegistrationBean` live here rather than in
// core, which keeps no servlet types in Flint; `ServletRegistrationBean` folds in its
// `DynamicRegistrationBean` base into `RegistrationBean`; the configurable factory has the settings Flint's engine
// supports; `DelegatingFilterProxyRegistrationBean`'s filter is a private lazy proxy, which is what Boot's subclass of
// spring-web's `DelegatingFilterProxy` (with `initFilterBean` skipped) does, until flint.web has the proxy.

/// `org.springframework.boot.web.server.servlet`: servlet web server support.
module flint.boot.web.server.servlet;

import flint.boot.web.server : Shutdown, WebServer;
import flint.context : ApplicationContext, ApplicationContextAware;
import flint.engine.aot.fast : FastFilter, FastFilterEffect;
import flint.core : Ordered;
import flint.jakarta.servlet : DispatcherType, Filter, FilterChain, Servlet, ServletContext,
    ServletRequest, ServletResponse;

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

/// Registers a filter: its URL patterns or servlet names (`/*` when neither is given), dispatcher types (by default
/// every type for a `OncePerRequestFilter` and `REQUEST` for any other filter) and whether it matches after the
/// filters declared in the deployment.
abstract class AbstractFilterRegistrationBean : RegistrationBean
{
    private static immutable string[] DEFAULT_URL_MAPPINGS = ["/*"];

    private string name;
    private string[] urlPatterns;
    private string[] servletNames;
    private DispatcherType[] dispatcherTypes;
    // Boot's `dispatcherTypes != null`: D has no null array distinct from an empty one, and Boot keeps an empty set.
    private bool dispatcherTypesSet;
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
        if (name.length)
            return name;
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

    /// Set the dispatcher types, an empty set included; until they are set, `getDispatcherTypes` decides from the
    /// filter.
    void setDispatcherTypes(DispatcherType[] dispatcherTypes...) pure nothrow
    {
        this.dispatcherTypes = dispatcherTypes.dup;
        this.dispatcherTypesSet = true;
    }

    /// The dispatcher types: those set, else Boot's `determineDispatcherTypes`: every type for a
    /// `OncePerRequestFilter`, which guards against running twice itself (and by default skips error dispatches),
    /// and `REQUEST` for any other filter.
    DispatcherType[] getDispatcherTypes()
    {
        import std.traits : EnumMembers;

        if (dispatcherTypesSet)
            return dispatcherTypes.dup;
        if (isOncePerRequestFilter(cast(Object) getFilter()))
            return [EnumMembers!DispatcherType].dup;
        return [DispatcherType.REQUEST];
    }

    // Boot's ClassUtils.isPresent and instanceof check, by class name: flint:web's OncePerRequestFilter is optional
    // here, as spring-web is for spring-boot-web-server.
    private static bool isOncePerRequestFilter(Object filter) nothrow
    {
        for (auto type = filter is null ? null : typeid(filter); type !is null; type = type.base)
            if (type.name == "flint.web.filter.OncePerRequestFilter")
                return true;
        return false;
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

/// Registers a filter that delegates to the bean named `targetBeanName`, looked up on the first request, so the bean is
/// created with the rest of the context rather than when the server starts.
class DelegatingFilterProxyRegistrationBean : AbstractFilterRegistrationBean, ApplicationContextAware
{
    private ApplicationContext applicationContext;
    private string targetBeanName;

    /// For the filter bean `targetBeanName`; `servletRegistrationBeans` restrict it to those servlets.
    this(string targetBeanName, ServletRegistrationBean[] servletRegistrationBeans...)
    {
        import flint.java.lang : IllegalArgumentException;

        if (targetBeanName.length == 0)
            throw new IllegalArgumentException("'targetBeanName' must not be empty");
        this.targetBeanName = targetBeanName;
        setName(targetBeanName);
        string[] names;
        foreach (registration; servletRegistrationBeans)
            names ~= registration.getServletName();
        if (names.length)
            setServletNames(names);
    }

    /// Set the context the filter bean is looked up in.
    void setApplicationContext(ApplicationContext applicationContext)
    {
        this.applicationContext = applicationContext;
    }

    /// The name of the filter bean.
    package(flint.boot.web.server) string getTargetBeanName() const pure nothrow @nogc
    {
        return targetBeanName;
    }

    /// A proxy to the filter bean.
    override Filter getFilter()
    {
        import flint.java.lang : IllegalStateException;

        if (applicationContext is null)
            throw new IllegalStateException("ApplicationContext has not been injected");
        return new DelegatingFilterProxy(targetBeanName, applicationContext);
    }
}

// spring-web's DelegatingFilterProxy as Boot's registration bean uses it: the delegate is looked up on the first
// request (initFilterBean is skipped), and its lifecycle stays with the context (targetFilterLifecycle is false).
private final class DelegatingFilterProxy : Filter, FastFilter
{
    private string targetBeanName;
    private ApplicationContext context;
    private Filter delegate_;

    this(string targetBeanName, ApplicationContext context) pure nothrow @nogc
    {
        this.targetBeanName = targetBeanName;
        this.context = context;
    }

    // init skips initFilterBean; destroy leaves the delegate to the context.
    mixin Filter.Defaults;

    void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
    {
        if (delegate_ is null)
            delegate_ = cast(Filter) context.getBean(targetBeanName);
        delegate_.doFilter(request, response, chain);
    }

    /// Flint's fast path (fast-path.md S4): the delegate's effect, when it states one. The container asks when it
    /// starts, after the context refreshed, so the delegate bean exists.
    bool fastEffect(bool secure, out FastFilterEffect effect)
    {
        if (delegate_ is null)
            delegate_ = cast(Filter) context.getBean(targetBeanName);
        auto fast = cast(FastFilter) delegate_;
        return fast !is null && fast.fastEffect(secure, effect);
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
