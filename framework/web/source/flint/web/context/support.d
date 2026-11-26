/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/web/context/support/
(ServletContextAwareProcessor.java, WebApplicationContextUtils.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated servlet callbacks and context lookup to D.
+/
module flint.web.context.support;

import flint.beans.factory.config : BeanPostProcessor;
import flint.engine.aot.objects : objectToString;
import flint.jakarta.servlet : ServletConfig, ServletContext;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.web.context : ServletConfigAware, ServletContextAware, WebApplicationContext;

@safe:

/// Supplies servlet context and config to aware beans before initialization.
class ServletContextAwareProcessor : BeanPostProcessor
{
    private ServletContext servletContext;
    private ServletConfig servletConfig;

    /// Lets a subclass supply the context or config later.
    protected this() pure nothrow @nogc
    {
    }

    /// With an explicit servlet context.
    this(ServletContext servletContext) pure nothrow @nogc
    {
        this(servletContext, null);
    }

    /// With a servlet config and its associated context.
    this(ServletConfig servletConfig) pure nothrow @nogc
    {
        this(null, servletConfig);
    }

    /// With an optional explicit context and config.
    this(ServletContext servletContext, ServletConfig servletConfig) pure nothrow @nogc
    {
        this.servletContext = servletContext;
        this.servletConfig = servletConfig;
    }

    /// Returns the context to inject, preferring the explicit value.
    protected ServletContext getServletContext()
    {
        if (servletContext !is null)
            return servletContext;
        auto config = getServletConfig();
        return config is null ? null : config.getServletContext();
    }

    /// Returns the servlet config to inject, or null.
    protected ServletConfig getServletConfig()
    {
        return servletConfig;
    }

    override Object postProcessBeforeInitialization(Object bean, string beanName)
    {
        if (auto context = getServletContext())
            if (auto aware = cast(ServletContextAware) bean)
                aware.setServletContext(context);
        if (auto config = getServletConfig())
            if (auto aware = cast(ServletConfigAware) bean)
                aware.setServletConfig(config);
        return bean;
    }

    override Object postProcessAfterInitialization(Object bean, string beanName)
    {
        return bean;
    }
}

/// Looks up application contexts published as servlet context attributes.
abstract class WebApplicationContextUtils
{
    /// Requires the root web context and surfaces failure during its startup.
    static WebApplicationContext getRequiredWebApplicationContext(ServletContext servletContext)
    {
        auto context = getWebApplicationContext(servletContext);
        if (context is null)
            throw new IllegalStateException("No WebApplicationContext found: no ContextLoaderListener registered?");
        return context;
    }

    /// Returns the root web context, or null if no root was published.
    static WebApplicationContext getWebApplicationContext(ServletContext servletContext)
    {
        return getWebApplicationContext(servletContext, WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE);
    }

    /// Reads the named context attribute and propagates any recorded startup failure.
    static WebApplicationContext getWebApplicationContext(ServletContext servletContext, string attributeName)
    {
        if (servletContext is null)
            throw new IllegalArgumentException("ServletContext must not be null");

        auto attribute = servletContext.getAttribute(attributeName);
        if (attribute.isNull())
            return null;
        auto object = attribute.asObject();

        if (auto context = cast(WebApplicationContext) object)
            return context;
        if (auto failure = cast(RuntimeException) object)
            throw failure;
        if (auto failure = cast(Error) object)
            throw failure;
        if (auto failure = cast(Exception) object)
            throw new IllegalStateException(failure);

        const description = object is null ? attribute.toString() : objectToString(object);
        throw new IllegalStateException("Context attribute is not of type WebApplicationContext: " ~ description);
    }
}
