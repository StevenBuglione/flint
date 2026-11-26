module flint.test.web.web_application_context_lookup_tests;

import flint.context : ApplicationContext;
import flint.context.support : GenericApplicationContext;
import flint.engine.aot.any : Any;
import flint.jakarta.servlet : ServletContext;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.mock.web : MockServletContext;
import flint.web.context : WebApplicationContext;
import flint.web.context.support : WebApplicationContextUtils;
import std.exception : assertThrown;

@safe:

private class LookupContext : GenericApplicationContext, WebApplicationContext
{
    private ServletContext servletContext;

    this(ServletContext servletContext)
    {
        super();
        this.servletContext = servletContext;
    }

    ServletContext getServletContext()
    {
        return servletContext;
    }
}

private alias Lookup = WebApplicationContextUtils;

@("Flint.WebApplicationContextUtils.rootAndNamedContextIdentity")
unittest
{
    auto servlet = new MockServletContext;
    auto root = new LookupContext(servlet);
    auto child = new LookupContext(null);
    ApplicationContext parent = root;
    assert(cast(WebApplicationContext) parent is root);
    assert(WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE
            == "org.springframework.web.context.WebApplicationContext.ROOT");

    servlet.setAttribute("org.springframework.web.context.WebApplicationContext.ROOT", Any.of(parent));
    servlet.setAttribute("dispatcher", Any.of(cast(WebApplicationContext) child));
    assert(Lookup.getWebApplicationContext(servlet) is root);
    assert(Lookup.getRequiredWebApplicationContext(servlet).getServletContext() is servlet);
    assert(Lookup.getWebApplicationContext(servlet, "dispatcher") is child);
    assert(child.getServletContext() is null);
}

@("Flint.WebApplicationContextUtils.distinguishesAbsentAndInvalidAttributes")
unittest
{
    auto servlet = new MockServletContext;
    assert(Lookup.getWebApplicationContext(servlet) is null);
    assert(Lookup.getWebApplicationContext(servlet, "missing") is null);
    assertThrown!IllegalArgumentException(Lookup.getWebApplicationContext(null));
    assertThrown!IllegalStateException(Lookup.getRequiredWebApplicationContext(servlet));

    servlet.setAttribute("dispatcher", Any.of("not a context"));
    assertThrown!IllegalStateException(Lookup.getWebApplicationContext(servlet, "dispatcher"));
}

@("Flint.WebApplicationContextUtils.propagatesStartupFailures")
unittest
{
    auto servlet = new MockServletContext;
    auto runtimeFailure = new IllegalArgumentException("root startup");
    servlet.setAttribute(WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, Any.of(runtimeFailure));
    try
    {
        Lookup.getWebApplicationContext(servlet);
        assert(false, "expected the original runtime exception");
    }
    catch (IllegalArgumentException failure)
        assert(failure is runtimeFailure);

    auto checkedFailure = new Exception("checked startup failure");
    servlet.setAttribute("dispatcher", Any.of(checkedFailure));
    try
    {
        Lookup.getWebApplicationContext(servlet, "dispatcher");
        assert(false, "expected an IllegalStateException carrying the checked failure");
    }
    catch (IllegalStateException failure)
        assert(failure.getCause() is checkedFailure);
}

@("Flint.WebApplicationContextUtils.rethrowsStartupError")
@system unittest
{
    auto servlet = new MockServletContext;
    servlet.setAttribute("dispatcher", Any.of(new Error("dispatcher startup")));
    assertThrown!Error(Lookup.getWebApplicationContext(servlet, "dispatcher"));
}
