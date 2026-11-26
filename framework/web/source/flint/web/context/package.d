/++
`org.springframework.web.context`: web application contexts and servlet-context callbacks.

Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/web/context/
(ServletContextAware.java, WebApplicationContext.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook.
+/
module flint.web.context;

import flint.beans.factory : Aware;
import flint.context : ApplicationContext;
import flint.jakarta.servlet : ServletContext;

@safe:

/// An application context associated with a servlet application.
interface WebApplicationContext : ApplicationContext
{
    /// The ServletContext attribute holding the root application context or its startup failure.
    enum string ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE = "org.springframework.web.context.WebApplicationContext.ROOT";

    enum string SCOPE_REQUEST = "request"; ///
    enum string SCOPE_SESSION = "session"; ///
    enum string SCOPE_APPLICATION = "application"; ///
    enum string SERVLET_CONTEXT_BEAN_NAME = "servletContext"; ///
    enum string CONTEXT_PARAMETERS_BEAN_NAME = "contextParameters"; ///
    enum string CONTEXT_ATTRIBUTES_BEAN_NAME = "contextAttributes"; ///

    /// The servlet context for this application, or null if none is associated.
    ServletContext getServletContext();
}

/// `ServletContextAware`: a bean that wants to know the `ServletContext` it runs in.
interface ServletContextAware : Aware
{
    /// Called after population, before initialization callbacks.
    void setServletContext(ServletContext servletContext);
}
