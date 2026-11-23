// Ported from spring-boot v4.2.0: core/spring-boot-test/src/main/java/org/springframework/boot/test/context/SpringBootTest.java
// with TestConfiguration.java and SpringBootTestContextBootstrapper.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: "Spring" becomes "Flint"; the JUnit extension and TestContext bootstrapper become
// `FlintBootTestContext`, which a test (or the generated test runner) calls with the test type and the
// application type; the application class is found from `classes` or given explicitly instead of by package search.

/// `org.springframework.boot.test.context`: testing a Flint Boot application.
///
/// ```d
/// @FlintBootTest(properties: ["greeting.prefix=Hi"])
/// @AutoConfigureMockMvc
/// final class GreetingControllerTests
/// {
///     @Autowired MockMvc mockMvc;
///     ...
/// }
/// ```
///
/// `FlintBootTestContext.start!(Test, App)` runs `App` as `@FlintBootTest` on `Test` describes it. The test's
/// properties have the highest precedence, as Boot's "Inlined Test Properties". `args` are the command line. The
/// web environment picks the context and the port: `MOCK` uses a servlet context without a server, `RANDOM_PORT`
/// sets `server.port=0`, `DEFINED_PORT` keeps the configured port, and `NONE` runs a plain context.
module flint.boot.test.context;

import flint.boot : ApplicationContextFactory, ClassRef, FlintApplication, WebApplicationType;
import flint.boot.internal.context : ConfigurableApplicationContext;

@safe:

/// Marks a test that runs the whole application.
struct FlintBootTest
{
    /// The kind of web environment the test runs in.
    enum WebEnvironment
    {
        /// A mock servlet environment: no server, MockMvc against the dispatcher.
        MOCK,
        /// An embedded server on a random port.
        RANDOM_PORT,
        /// An embedded server on the configured port.
        DEFINED_PORT,
        /// No web environment.
        NONE
    }

    /// Whether the test runs the application's `main`.
    enum UseMainMethod
    {
        /// Always.
        ALWAYS,
        /// Never: the application is started directly.
        NEVER,
        /// When the application declares one.
        WHEN_AVAILABLE
    }

    /// Properties in `key=value` form; an alias of `properties`.
    string[] value;
    /// Properties in `key=value` form, added with the highest precedence.
    string[] properties;
    /// Application arguments.
    string[] args;
    /// The configuration classes; the `@FlintBootConfiguration` application class when empty.
    ClassRef[] classes;
    /// The web environment.
    WebEnvironment webEnvironment = WebEnvironment.MOCK;
    /// Whether to use the application's `main`.
    UseMainMethod useMainMethod = UseMainMethod.NEVER;
}

/// Whether the web environment starts an embedded server.
bool isEmbedded(FlintBootTest.WebEnvironment environment) pure nothrow @nogc
{
    return environment == FlintBootTest.WebEnvironment.RANDOM_PORT
        || environment == FlintBootTest.WebEnvironment.DEFINED_PORT;
}

/// Marks a `@Configuration` class that only tests use; component scanning of the application skips it.
struct TestConfiguration
{
    /// The bean name of the configuration.
    string value;
    /// Whether `@Bean` methods are proxied.
    bool proxyBeanMethods = true;
}

/// Starts the application context of a `@FlintBootTest`, as Boot's `SpringBootTestContextBootstrapper` and
/// `SpringBootContextLoader` do.
struct FlintBootTestContext
{
    /// Start `App` for the test type `Test`, whose `@FlintBootTest` is read from its descriptor, with contexts
    /// from `factory`. Configure the application further with `customize` (resource readers in tests).
    static ConfigurableApplicationContext start(Test, App)(ApplicationContextFactory factory,
            scope void delegate(FlintApplication) @safe customize = null)
    {
        import flint.engine.aot.descriptor : descriptorOf;
        import flint.engine.aot.name : typeNameOf;

        auto descriptor = descriptorOf!Test();
        const found = descriptor.annotation(typeNameOf!FlintBootTest);
        const annotation = found is null ? FlintBootTest.init : found.value.get!FlintBootTest;
        return start(annotation, ClassRef(typeNameOf!App), factory, customize);
    }

    /// The erased form: start the application `app` as `annotation` describes.
    static ConfigurableApplicationContext start(const FlintBootTest annotation, ClassRef app,
            ApplicationContextFactory factory, scope void delegate(FlintApplication) @safe customize = null)
    {
        auto application = new FlintApplication(annotation.classes.length ? annotation.classes.dup : [
            app
        ]);
        application.setMainApplicationClass(app);
        application.setApplicationContextFactory(factory);
        auto properties = inlinedProperties(annotation.value ~ annotation.properties);
        final switch (annotation.webEnvironment)
        {
        case FlintBootTest.WebEnvironment.MOCK:
            application.setWebApplicationType(WebApplicationType.SERVLET);
            properties["flint.test.web-environment"] = "mock";
            break;
        case FlintBootTest.WebEnvironment.RANDOM_PORT:
            application.setWebApplicationType(WebApplicationType.SERVLET);
            properties["server.port"] = "0";
            break;
        case FlintBootTest.WebEnvironment.DEFINED_PORT:
            application.setWebApplicationType(WebApplicationType.SERVLET);
            break;
        case FlintBootTest.WebEnvironment.NONE:
            application.setWebApplicationType(WebApplicationType.NONE);
            break;
        }
        application.setTestProperties(properties);
        if (customize !is null)
            customize(application);
        return application.run(annotation.args.dup);
    }

    /// `key=value` and `key:value` pairs, as Boot's `TestPropertySourceUtils.convertInlinedPropertiesToMap`.
    static string[string] inlinedProperties(const string[] pairs) pure
    {
        string[string] result;
        foreach (pair; pairs)
        {
            long split = -1;
            foreach (index, char ch; pair)
            {
                if (ch == '=' || ch == ':')
                {
                    split = cast(long) index;
                    break;
                }
            }
            if (split > 0)
                result[pair[0 .. cast(size_t) split]] = pair[cast(size_t) split + 1 .. $];
            else
                result[pair] = "";
        }
        return result;
    }
}
