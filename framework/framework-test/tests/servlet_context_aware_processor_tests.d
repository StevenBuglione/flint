module flint.test.web.servlet_context_aware_processor_tests;

import flint.jakarta.servlet : ServletConfig, ServletContext;
import flint.mock.web : MockServletContext;
import flint.web.context : ServletConfigAware, ServletContextAware;
import flint.web.context.support : ServletContextAwareProcessor;

@safe:

private class TestServletConfig : ServletConfig
{
    private ServletContext context;

    this(ServletContext context)
    {
        this.context = context;
    }

    string getServletName()
    {
        return "dispatcher";
    }

    ServletContext getServletContext()
    {
        return context;
    }

    string getInitParameter(string name)
    {
        return null;
    }

    string[] getInitParameterNames()
    {
        return null;
    }
}

private class AwareBean : ServletContextAware, ServletConfigAware
{
    ServletContext context;
    ServletConfig config;
    int callbacks;

    void setServletContext(ServletContext context)
    {
        this.context = context;
        callbacks = callbacks * 10 + 1;
    }

    void setServletConfig(ServletConfig config)
    {
        this.config = config;
        callbacks = callbacks * 10 + 2;
    }
}

private class LateProcessor : ServletContextAwareProcessor
{
    ServletConfig config;

    protected override ServletConfig getServletConfig()
    {
        return config;
    }
}

@("Flint.ServletContextAwareProcessor.prefersExplicitContextAndInjectsInOrder")
unittest
{
    auto servlet = new MockServletContext;
    auto config = new TestServletConfig(new MockServletContext);
    auto processor = new ServletContextAwareProcessor(servlet, config);
    auto bean = new AwareBean;

    assert(processor.postProcessBeforeInitialization(bean, "aware") is bean);
    assert(bean.context is servlet);
    assert(bean.config is config);
    assert(bean.callbacks == 12);
}

@("Flint.ServletContextAwareProcessor.resolvesContextFromConfig")
unittest
{
    auto servlet = new MockServletContext;
    auto config = new TestServletConfig(servlet);
    auto processor = new ServletContextAwareProcessor(config);
    auto bean = new AwareBean;

    assert(processor.postProcessBeforeInitialization(bean, "aware") is bean);
    assert(bean.context is servlet);
    assert(bean.config is config);
    assert(bean.callbacks == 12);
}

@("Flint.ServletContextAwareProcessor.leavesNonAwareAndAfterInitializationUntouched")
unittest
{
    auto servlet = new MockServletContext;
    auto processor = new ServletContextAwareProcessor(servlet);
    auto ordinary = new Object;
    assert(processor.postProcessBeforeInitialization(ordinary, "ordinary") is ordinary);

    auto bean = new AwareBean;
    assert(processor.postProcessAfterInitialization(bean, "aware") is bean);
    assert(bean.callbacks == 0);
    assert(processor.postProcessBeforeInitialization(bean, "aware") is bean);
    assert(bean.context is servlet);
    assert(bean.config is null);
    assert(bean.callbacks == 1);
}

@("Flint.ServletContextAwareProcessor.resolvesLateConfigThroughSubclass")
unittest
{
    auto processor = new LateProcessor;
    auto bean = new AwareBean;
    assert(processor.postProcessBeforeInitialization(bean, "aware") is bean);
    assert(bean.callbacks == 0);

    auto servlet = new MockServletContext;
    processor.config = new TestServletConfig(servlet);
    assert(processor.postProcessBeforeInitialization(bean, "aware") is bean);
    assert(bean.context is servlet);
    assert(bean.config is processor.config);
    assert(bean.callbacks == 12);
}
