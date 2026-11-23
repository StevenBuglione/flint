// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/builder/
// SpringApplicationBuilderTests.java: the tests boot_tests/application_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Mockito's spy context records the parent it is given; `Class<?>` sources are
// `ClassRef`s; the shutdown-hook assertions are dropped (JVM shutdown hooks).
// Not ported: contextWithClassLoader and parentContextWithClassLoader (Java class loaders),
// parentContextCreationWithChildShutdown (the JVM shutdown hook registry), sourcesWithBoundSources
// (`spring.main.sources` names classes loaded at run time; Flint registers its sources at build time).
module boot_tests.builder_upstream_test;

import boot_tests.upstream_support : MemoryReader;
import flint.boot : ApplicationArguments, ApplicationContextFactory, ClassRef, WebApplicationType;
import flint.boot.builder : FlintApplicationBuilder;
import flint.context : ApplicationContext, ConfigurableApplicationContext;
import flint.context.support : GenericApplicationContext;
import flint.core.env : Profiles;

@safe:

/// `SpringApplicationBuilderTests.ExampleConfig`.
final class ExampleConfig
{
}

/// `SpringApplicationBuilderTests.ChildConfig`.
final class ChildConfig
{
}

private enum exampleConfig = ClassRef("boot_tests.builder_upstream_test.ExampleConfig");
private enum childConfig = ClassRef("boot_tests.builder_upstream_test.ChildConfig");

/// `SpyApplicationContext`: remembers the parent it was given.
private final class SpyApplicationContext : GenericApplicationContext
{
    bool parentSet;

    override void setParent(ApplicationContext parent)
    {
        parentSet = true;
        super.setParent(parent);
    }
}

private final class SpyFactory : ApplicationContextFactory
{
    ConfigurableApplicationContext create(WebApplicationType)
    {
        return new SpyApplicationContext;
    }
}

/// A builder over in-memory config files, quiet.
private FlintApplicationBuilder builder(ClassRef[] sources...)
{
    auto result = new FlintApplicationBuilder(sources);
    result.getApplication().setResourceReader(new MemoryReader(null));
    result.getApplication().setEnvironmentVariables(null);
    result.getApplication().setOutput((string) {});
    return result;
}

version (FlintApplicationApi)
{
    // Gap: the builder has no `properties(Properties)`, and no resource loader or `createFlintApplication` hook.
    @("propertiesAsProperties") unittest
    {
        import flint.java.util : Properties;

        auto properties = new Properties;
        properties.setProperty("bar", "foo");
        auto application = builder().sources(exampleConfig).contextFactory(new SpyFactory).properties(properties);
        auto context = application.run();
        scope (exit)
            context.close();
        assert(context.getEnvironment().getProperty("bar") == "foo");
    }

    @("customApplicationWithResourceLoader") unittest
    {
        import flint.boot : FlintApplication;
        import flint.core.io : DefaultResourceLoader, ResourceLoader;

        final class CustomFlintApplication : FlintApplication
        {
            ResourceLoader resourceLoader;

            this(ResourceLoader resourceLoader, ClassRef[] primarySources...)
            {
                super(resourceLoader, primarySources);
                this.resourceLoader = resourceLoader;
            }
        }

        final class CustomBuilder : FlintApplicationBuilder
        {
            this(ResourceLoader resourceLoader, ClassRef[] sources...)
            {
                super(resourceLoader, sources);
            }

            protected override FlintApplication createFlintApplication(ResourceLoader resourceLoader,
                    ClassRef[] sources...)
            {
                return new CustomFlintApplication(resourceLoader, sources);
            }
        }

        auto resourceLoader = new DefaultResourceLoader;
        const application = new CustomBuilder(resourceLoader, exampleConfig).build();
        auto custom = cast(const CustomFlintApplication) application;
        assert(custom !is null && custom.resourceLoader is resourceLoader);
    }
}

version (FlintApplicationContextHierarchy)
{
    // Gap: the builder has no context hierarchies (`parent`, `child`, `sibling`) and no `environment`.
    @("parentContextCreationThatIsRunDirectly") unittest
    {
        auto application = builder(childConfig).contextFactory(new SpyFactory);
        application.parent(exampleConfig);
        auto context = application.run("foo.bar=baz");
        scope (exit)
            context.close();
        assert((cast(SpyApplicationContext) context).parentSet);
        auto parent = context.getParent();
        assert(parent !is null);
        assert(parent.getBean!ApplicationArguments().getNonOptionArgs() == ["foo.bar=baz"]);
        assert(context.getBean!ApplicationArguments().getNonOptionArgs() == ["foo.bar=baz"]);
    }

    @("parentContextCreationThatIsBuiltThenRun") unittest
    {
        auto application = builder(childConfig).contextFactory(new SpyFactory);
        application.parent(exampleConfig);
        auto context = application.build("a=alpha").run(["b=bravo"]);
        scope (exit)
            context.close();
        assert((cast(SpyApplicationContext) context).parentSet);
        auto parent = context.getParent();
        assert(parent !is null);
        assert(parent.getBean!ApplicationArguments().getNonOptionArgs() == ["a=alpha"]);
        assert(context.getBean!ApplicationArguments().getNonOptionArgs() == ["b=bravo"]);
    }

    @("parentFirstCreation") unittest
    {
        auto application = builder(exampleConfig).child(childConfig);
        application.contextFactory(new SpyFactory);
        auto context = application.run();
        scope (exit)
            context.close();
        assert((cast(SpyApplicationContext) context).parentSet);
    }

    @("parentFirstCreationWithProfileAndDefaultArgs") unittest
    {
        auto application = builder(exampleConfig).profiles("node").properties("transport=redis")
            .child(childConfig).web(WebApplicationType.NONE);
        application.getApplication()
            .setResourceReader(new MemoryReader([
                "resources/application-node.properties": "bar=spam\n"
        ]));
        auto context = application.run();
        scope (exit)
            context.close();
        assert(context.getEnvironment().acceptsProfiles(Profiles.of("node")));
        assert(context.getEnvironment().getProperty("transport") == "redis");
        auto parent = context.getParent();
        assert(parent !is null);
        assert(parent.getEnvironment().acceptsProfiles(Profiles.of("node")));
        assert(parent.getEnvironment().getProperty("transport") == "redis");
        // only defined in node profile
        assert(context.getEnvironment().getProperty("bar") == "spam");
    }

    @("parentFirstWithDifferentProfile") unittest
    {
        auto application = builder(exampleConfig).profiles("node").properties("transport=redis")
            .child(childConfig).profiles("admin").web(WebApplicationType.NONE);
        auto context = application.run();
        scope (exit)
            context.close();
        assert(context.getEnvironment().acceptsProfiles(Profiles.of("node", "admin")));
        auto parent = context.getParent();
        assert(parent !is null);
        assert(!parent.getEnvironment().acceptsProfiles(Profiles.of("admin")));
    }

    @("parentWithDifferentProfile") unittest
    {
        auto shared_ = builder(exampleConfig).profiles("node").properties("transport=redis");
        auto application = shared_.child(childConfig).profiles("admin").web(WebApplicationType.NONE);
        shared_.profiles("parent");
        auto context = application.run();
        scope (exit)
            context.close();
        assert(context.getEnvironment().acceptsProfiles(Profiles.of("node", "admin")));
        auto parent = context.getParent();
        assert(parent !is null);
        assert(parent.getEnvironment().acceptsProfiles(Profiles.of("node", "parent")));
        assert(!parent.getEnvironment().acceptsProfiles(Profiles.of("admin")));
    }

    @("parentFirstWithDifferentProfileAndExplicitEnvironment") unittest
    {
        import flint.core.env : StandardEnvironment;

        auto application = builder(exampleConfig).environment(new StandardEnvironment).profiles("node")
            .properties("transport=redis").child(childConfig).profiles("admin").web(WebApplicationType.NONE);
        auto context = application.run();
        scope (exit)
            context.close();
        assert(context.getEnvironment().acceptsProfiles(Profiles.of("node", "admin")));
        // Now they share an Environment explicitly so there's no way to keep the profiles separate
        auto parent = context.getParent();
        assert(parent !is null);
        assert(parent.getEnvironment().acceptsProfiles(Profiles.of("admin")));
    }

    @("parentContextIdentical") unittest
    {
        auto application = builder(exampleConfig);
        application.parent(exampleConfig);
        application.contextFactory(new SpyFactory);
        auto context = application.run();
        scope (exit)
            context.close();
        assert((cast(SpyApplicationContext) context).parentSet);
    }
}

version (FlintApplicationInitializers)
{
    // Gap: FlintApplication has no ApplicationContextInitializers (Boot's defaults are the context id, the
    // configuration warnings and the server port ones, plus the parent's for a child).
    @("initializersCreatedOnce") unittest
    {
        auto application = builder(exampleConfig).web(WebApplicationType.NONE);
        auto context = application.run();
        scope (exit)
            context.close();
        assert(application.getApplication().getInitializers().length == 3);
    }

    @("initializersCreatedOnceForChild") unittest
    {
        auto application = builder(exampleConfig).child(childConfig).web(WebApplicationType.NONE);
        auto context = application.run();
        scope (exit)
            context.close();
        assert(application.getApplication().getInitializers().length == 4);
    }

    @("initializersIncludeDefaults") unittest
    {
        auto application = builder(exampleConfig).web(WebApplicationType.NONE)
            .initializers((ConfigurableApplicationContext) {});
        auto context = application.run();
        scope (exit)
            context.close();
        assert(application.getApplication().getInitializers().length == 4);
    }
}

version (FlintBootstrapRegistry)
{
    // Gap: there is no BootstrapRegistry, so no addBootstrapRegistryInitializer.
    @("addBootstrapRegistryInitializer") unittest
    {
        import flint.boot.bootstrap : BootstrapContextClosedEvent, BootstrapRegistry;

        final class Text
        {
            string value = "spring";
        }

        auto application = builder(exampleConfig).web(WebApplicationType.NONE)
            .addBootstrapRegistryInitializer((BootstrapRegistry registry) {
                registry.addCloseListener((BootstrapContextClosedEvent event) {
                    event.getApplicationContext().getBeanFactory().registerSingleton("test", new Text);
                });
            });
        auto context = application.run();
        scope (exit)
            context.close();
        assert(context.getBean!Text("test").value == "spring");
    }
}

version (FlintEnvironmentPrefix)
{
    // Gap: there is no environment prefix.
    @("setEnvironmentPrefix") unittest
    {
        auto application = builder(exampleConfig).environmentPrefix("test");
        assert(application.getApplication().getEnvironmentPrefix() == "test");
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
