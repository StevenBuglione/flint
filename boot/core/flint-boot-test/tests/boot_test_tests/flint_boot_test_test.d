/// Flint tests modelled on spring-boot's SpringBootTestArgsTests, SpringBootTest*PropertiesTests and
/// SpringBootTestWebEnvironment*Tests (which need a real context and run once framework-core's context lands):
/// inlined properties, args and the web environment, over a stub context.
module boot_test_tests.flint_boot_test_test;

import flint.boot : ApplicationContextFactory, ApplicationEnvironment, ClassRef, FlintApplication, WebApplicationType;
import flint.boot.context.config : ConfigDataResourceReader;
import flint.boot.internal.context : ConfigurableApplicationContext;
import flint.boot.test.context : FlintBootTest, FlintBootTestContext;
import flint.engine.aot.any : Any;
import flint.engine.aot.bean : BeanFactory;

@safe:

private final class NoBeans : BeanFactory
{
    Object getBean(string)
    {
        return null;
    }

    Object getBeanOfType(string, string = null)
    {
        return null;
    }

    Object findBeanOfType(string, string = null)
    {
        return null;
    }

    Object[] getBeansOfType(string)
    {
        return null;
    }

    Any resolveValue(string, string)
    {
        return Any.init;
    }

    void bind(string, Any)
    {
    }

    Any bindConstructor(string, string)
    {
        return Any.init;
    }
}

private final class Context : ConfigurableApplicationContext
{
    Object environment;

    string getId()
    {
        return "test";
    }

    void setEnvironment(Object environment)
    {
        this.environment = environment;
    }

    void registerSingleton(string, Object)
    {
    }

    void refresh()
    {
    }

    BeanFactory getBeanFactory()
    {
        return new NoBeans;
    }

    bool isActive()
    {
        return true;
    }

    void close()
    {
    }

    void awaitTermination()
    {
    }
}

private final class Factory : ApplicationContextFactory
{
    Context context;
    WebApplicationType type;

    ConfigurableApplicationContext create(WebApplicationType webApplicationType)
    {
        type = webApplicationType;
        context = new Context;
        return context;
    }
}

private final class Files : ConfigDataResourceReader
{
    const(ubyte)[] read(string path)
    {
        return path == "resources/application.properties" ? cast(const(ubyte)[]) "value=file\nother=file\n" : null;
    }

    string[] subdirectories(string)
    {
        return null;
    }

    bool directoryExists(string)
    {
        return false;
    }
}

/// The application under test.
final class Application
{
}

private enum FlintBootTest propertiesTest = () {
    FlintBootTest annotation;
    annotation.properties = ["value=123", "spring.application.name:demo"];
    annotation.args = ["--option=yes"];
    return annotation;
}();

private template withEnvironment(FlintBootTest.WebEnvironment environment)
{
    enum FlintBootTest withEnvironment = () {
        FlintBootTest annotation;
        annotation.webEnvironment = environment;
        return annotation;
    }();
}

@propertiesTest private final class PropertiesTest
{
}

@withEnvironment!(FlintBootTest.WebEnvironment.RANDOM_PORT) private final class RandomPortTest
{
}

@withEnvironment!(FlintBootTest.WebEnvironment.NONE) private final class NoWebTest
{
}

private ApplicationEnvironment start(Test)(Factory factory)
{
    auto context = FlintBootTestContext.start!(Test, Application)(factory, (FlintApplication application) {
        application.setResourceReader(new Files);
        application.setEnvironmentVariables(null);
        application.setOutput((string) {});
    });
    return cast(ApplicationEnvironment)(cast(Context) context).environment;
}

unittest
{
    // SpringBootTestPropertiesTests: inlined properties win over application.properties.
    auto factory = new Factory;
    auto environment = start!PropertiesTest(factory);
    assert(environment.getProperty("value") == "123");
    assert(environment.getProperty("other") == "file");
    assert(environment.getProperty("flint.application.name") == "demo");
}

unittest
{
    // SpringBootTestArgsTests: args reach the environment as command-line properties.
    auto environment = start!PropertiesTest(new Factory);
    assert(environment.getProperty("option") == "yes");
}

unittest
{
    // SpringBootTestWebEnvironmentMockTests: MOCK is a servlet context without a server.
    auto factory = new Factory;
    auto environment = start!Application(factory);
    assert(factory.type == WebApplicationType.SERVLET);
    assert(environment.getProperty("flint.test.web-environment") == "mock");
}

unittest
{
    // SpringBootTestWebEnvironmentRandomPortTests: server.port=0.
    auto factory = new Factory;
    auto environment = start!RandomPortTest(factory);
    assert(factory.type == WebApplicationType.SERVLET);
    assert(environment.getProperty("server.port") == "0");
}

unittest
{
    auto factory = new Factory;
    start!NoWebTest(factory);
    assert(factory.type == WebApplicationType.NONE);
}

unittest
{
    assert(FlintBootTestContext.inlinedProperties(["a=1", "b:2", "c"]) == [
        "a": "1",
        "b": "2",
        "c": ""
    ]);
}
