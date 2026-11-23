// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/SpringApplicationTests.java
// with ResourceBannerTests.java, StartupInfoLoggerTests.java, SpringApplicationBannerPrinterTests.java and
// SpringBootVersionTests.java from the same directory: the tests boot_tests/application_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the context is a real `GenericApplicationContext` whose refresh registers the
// test's beans as Flint AOT's generated definitions (or Boot's initializers) would; output is captured through
// `setOutput` instead of OutputCaptureExtension; a `StandardEnvironment` handed to `setEnvironment` only to be read
// back is the context's environment; `MockEnvironment` default profiles are `flint.profiles.default`; Java system
// properties are environment variables; the banner mode is observed in the output (Boot reads a private field);
// StartupInfoLogger is folded into `FlintApplication`, so its lines are read from a run, with the process's own PID
// (`flint.application.pid` is Boot's copy of it) and "using Flint <version>" for "using Java <version>";
// SpringBootVersion is checked against flint-dependencies.json's release, Flint's gradle.properties.
// Not ported: SpringApplicationTests sourcesMustNotBeNull (a null D slice is the empty list),
// sourcesMustBeAccessible (Java constructor visibility), customEnvironment, customResourceLoader,
// customResourceLoaderFromConstructor and customBeanNameGenerator (Boot's BeanDefinitionLoader; Flint loads the AOT
// registry), nativeImageShouldCheckForJava25, missingAotInitializerTakesPrecedenceOverNativeImageRequirementsCheck,
// failureInANativeImageWritesFailureToSystemOut, shouldUseAotInitializer and
// shouldReportFriendlyErrorIfAotInitializerNotFound (GraalVM and Java's AOT mode), wildcardSources (XML bean
// definitions), exceptionFromRefreshIsHandledGracefully (SpringBootExceptionHandler, Java's uncaught-exception
// handler), registerShutdownHook, registerShutdownHookOff and deregistersShutdownHookForFailedApplicationContext
// (JVM shutdown hooks), headless, headlessFalse and headlessSystemPropertyTakesPrecedence (java.awt.headless),
// shouldStartDaemonThreadIfKeepAliveIsEnabled, shouldStopKeepAliveThreadIfContextIsClosed and
// shouldNotStopKeepAliveThreadIfChildContextIsClosed (Java's keep-alive thread); StartupInfoLoggerTests
// startingFormatWhenPidIsNotAvailable (Flint always reads its PID from the OS), startingFormatInAotMode (Java's
// AOT mode), startedWithoutUptimeFormat (Flint always reports an uptime) and restoredFormat (CRaC);
// SpringApplicationBannerPrinterTests shouldRegisterRuntimeHints (AOT runtime hints); DefaultApplicationArgumentsTests
// argumentsMustNotBeNull (a null D slice is the empty list).
module boot_tests.application_upstream_test;

import boot_tests.support : assertThrows;
import boot_tests.upstream_support : MemoryReader;
import flint.boot : ApplicationArguments, ApplicationContextFactory, ApplicationRunner, Banner,
    ClassRef, CommandLineRunner, FlintApplication, FlintBootVersion, WebApplicationType;
import flint.context : ConfigurableApplicationContext;
import flint.context.support : GenericApplicationContext;
import std.algorithm.searching : canFind;

@safe:

/// `SpringApplicationTests.ExampleConfig`.
final class ExampleConfig
{
}

/// A text bean, as `ExampleConfig.someBean` returns a `String`.
final class Text
{
    /// The text.
    string value;

    /// `value` as a bean.
    this(string value)
    {
        this.value = value;
    }
}

/// A context whose refresh first runs the test's registrations, as Flint AOT's generated definitions would.
private final class TestContext : GenericApplicationContext
{
    void delegate(TestContext) @safe[] registrations;
    Exception refreshFailure;

    override void refresh()
    {
        foreach (registration; registrations)
            registration(this);
        if (refreshFailure !is null)
            throw refreshFailure;
        super.refresh();
    }
}

private final class TestFactory : ApplicationContextFactory
{
    TestContext context;

    this(TestContext context)
    {
        this.context = context;
    }

    ConfigurableApplicationContext create(WebApplicationType)
    {
        return context;
    }
}

/// An application of `ExampleConfig` over a `TestContext`, its config files and environment variables in memory.
private final class Run
{
    FlintApplication application;
    TestContext context;
    string output;

    this(string[string] files, string[string] environment)
    {
        context = new TestContext;
        application = new FlintApplication(ClassRef("boot_tests.application_upstream_test.ExampleConfig"));
        application.setApplicationContextFactory(new TestFactory(context));
        application.setResourceReader(new MemoryReader(files));
        application.setEnvironmentVariables(environment);
        application.setWebApplicationType(WebApplicationType.NONE);
        application.setOutput((string text) { output ~= text; });
    }

    ConfigurableApplicationContext start(string[] args...)
    {
        return application.run(args.dup);
    }

    string property(string key)
    {
        return context.getEnvironment().getProperty(key);
    }

    bool bannerPrinted()
    {
        return output.canFind(":: Flint Boot ::");
    }
}

private Run prepare(string[string] files = null, string[string] environment = null)
{
    return new Run(files, environment);
}

/// Counts the runs of a runner, as `registerCountingRunner` does.
private final class CountingRunner : ApplicationRunner
{
    int calls;

    void run(ApplicationArguments)
    {
        calls++;
    }
}

private CountingRunner registerCountingRunner(Run run)
{
    auto runner = new CountingRunner;
    run.context.registrations ~= (TestContext context) {
        context.registerBean!CountingRunner("runner", () => runner);
    };
    return runner;
}

/// `AtomicInteger counter` of the lazy initialization configurations.
final class Counter
{
    /// The count.
    int value;
}

/// `LazyBean` and `NotLazyBean`: count their construction.
final class CountedBean
{
    /// Count one construction on `counter`.
    this(Counter counter)
    {
        counter.value++;
    }
}

private void registerCountedBeans(Run run, bool explicitlyNotLazy)
{
    import flint.beans.factory.config : BeanDefinition;

    run.context.registrations ~= (TestContext context) {
        auto counter = new Counter;
        context.registerBean!Counter("counter", () => counter);
        if (explicitlyNotLazy)
        {
            void delegate(BeanDefinition) @safe notLazy = (definition) {
                definition.setLazyInit(false);
            };
            context.registerBean!CountedBean("notLazyBean", () => new CountedBean(counter), notLazy);
        }
        else
            context.registerBean!CountedBean("lazyBean", () => new CountedBean(counter));
    };
}

private void registerSomeBeans(Run run)
{
    run.context.registrations ~= (TestContext context) {
        context.registerBean!Text("someBean", () => new Text("test"));
        context.registerBean!Text("someBean", () => new Text("override"));
    };
}

// ---- SpringApplicationTests ---------------------------------------------------------------------------------

version (FlintApplicationSourcesCheck)
{
    // Gap: an application without sources runs instead of failing with "No sources defined".
    @("sourcesMustNotBeEmpty") unittest
    {
        import flint.java.lang : IllegalStateException;

        auto application = new FlintApplication();
        application.setResourceReader(new MemoryReader(null));
        application.setOutput((string) {});
        assertThrows!IllegalStateException(() { application.run(null); }, "No sources defined");
    }
}

@("customBannerWithProperties") unittest
{
    auto run = prepare(["resources/banner.txt": "Running a Test!\n\n${test.property}"]);
    run.start("--test.property=123456");
    assert(run.output.canFind("Running a Test!\n\n123456"), run.output);
}

@("logsActiveProfilesWithoutProfileAndMultipleDefaults") unittest
{
    auto run = prepare();
    run.application.setDefaultProperties(["flint.profiles.default": "p0,default"]);
    run.start();
    const expected = `No active profile set, falling back to 2 default profiles: "p0", "default"`;
    assert(run.output.canFind(expected), run.output);
}

@("enableBannerInLogViaProperty") unittest
{
    auto run = prepare();
    run.start("--flint.main.banner-mode=log");
    // Banner.Mode.LOG: the banner is an INFO line of the application's log instead of printed output.
    assert(run.output.canFind(" INFO "), run.output);
    assert(run.output.canFind("ExampleConfig"), run.output);
    assert(run.output.canFind(" : \n  _____ _ _       _"), run.output);
}

@("triggersConfigFileApplicationListenerBeforeBinding") unittest
{
    auto run = prepare(["resources/bindtoapplication.properties": "flint.main.banner-mode=off\n"]);
    run.start("--flint.config.name=bindtoapplication");
    assert(!run.bannerPrinted(), run.output);
}

@("bindsSystemPropertyToSpringApplication") unittest
{
    auto run = prepare(null, ["FLINT_MAIN_BANNERMODE": "off"]);
    run.start();
    assert(!run.bannerPrinted(), run.output);
}

version (FlintBannerModeBoolean)
{
    // Gap: `flint.main.banner-mode=false` (YAML's `off`, a boolean) fails instead of meaning OFF.
    @("bindsYamlStyleBannerModeToSpringApplication") unittest
    {
        auto run = prepare();
        run.application.setDefaultProperties(["flint.main.banner-mode": "false"]);
        run.start();
        assert(!run.bannerPrinted(), run.output);
    }

    @("bindsBooleanAsStringBannerModeToSpringApplication") unittest
    {
        auto run = prepare();
        run.start("--flint.main.banner-mode=false");
        assert(!run.bannerPrinted(), run.output);
    }
}

version (FlintContextId)
{
    // Gap: the context id is not taken from `flint.application.name`.
    @("customId") unittest
    {
        import std.algorithm.searching : startsWith;

        auto run = prepare();
        auto context = run.start("--flint.application.name=foo");
        assert(context.getId().startsWith("foo"), context.getId());
    }
}

version (FlintDefaultContextType)
{
    // Gap: the default context is a GenericApplicationContext, not Boot's AnnotationConfigApplicationContext.
    @("defaultApplicationContext") unittest
    {
        import flint.context.annotation : AnnotationConfigApplicationContext;

        auto application = new FlintApplication(ClassRef("boot_tests.application_upstream_test.ExampleConfig"));
        application.setWebApplicationType(WebApplicationType.NONE);
        application.setResourceReader(new MemoryReader(null));
        application.setEnvironmentVariables(null);
        application.setOutput((string) {});
        auto context = application.run(null);
        scope (exit)
            context.close();
        assert(cast(AnnotationConfigApplicationContext) context !is null);
    }
}

@("propertiesFileEnhancesEnvironment") unittest
{
    auto run = prepare(["resources/application.properties": "foo=bucket\n"]);
    run.start();
    assert(run.property("foo") == "bucket");
}

@("addProfiles") unittest
{
    import flint.core.env : Profiles;

    auto run = prepare();
    run.application.setAdditionalProfiles("foo");
    run.start();
    assert(run.context.getEnvironment().acceptsProfiles(Profiles.of("foo")));
}

@("additionalProfilesOrderedBeforeActiveProfiles") unittest
{
    auto run = prepare();
    run.application.setAdditionalProfiles("foo");
    run.start("--flint.profiles.active=bar,spam");
    const active = run.context.getEnvironment().getActiveProfiles();
    assert(active == ["foo", "bar", "spam"], active[0]);
}

@("addProfilesOrderWithProperties") unittest
{
    auto run = prepare([
        "resources/application.properties": "my.property=fromapplicationproperties\n",
        "resources/application-other.properties": "my.property=fromotherpropertiesfile\n"
    ]);
    run.application.setAdditionalProfiles("other");
    run.start();
    // Active profile should win over default
    assert(run.property("my.property") == "fromotherpropertiesfile");
}

@("emptyCommandLinePropertySourceNotAdded") unittest
{
    auto run = prepare(["resources/application.properties": "foo=bucket\n"]);
    run.start();
    assert(run.property("foo") == "bucket");
}

version (FlintApplicationConversionService)
{
    // Gap: Boot's ApplicationConversionService and `setAddConversionService` do not exist.
    import flint.boot.convert : ApplicationConversionService;

    @("contextUsesApplicationConversionService") unittest
    {
        auto run = prepare();
        auto context = run.start();
        assert(cast(ApplicationConversionService) context.getBeanFactory().getConversionService() !is null);
        assert(cast(ApplicationConversionService) context.getConfigurableEnvironment().getConversionService() !is null);
    }

    @("contextWhenHasAddConversionServiceFalseUsesRegularConversionService") unittest
    {
        auto run = prepare();
        run.application.setAddConversionService(false);
        auto context = run.start();
        assert(context.getBeanFactory().getConversionService() is null);
        assert(cast(ApplicationConversionService) context.getConfigurableEnvironment().getConversionService() is null);
    }
}

version (FlintRunnerOrder)
{
    // Gap: runners run in registration order; Boot sorts them by Ordered and @Order.
    import flint.beans.factory.support : RootBeanDefinition;
    import flint.engine.aot.bean : AotBeanDefinition = BeanDefinition, AotBeanFactory = BeanFactory;
    import flint.engine.aot.name : typeNameOf;

    private string[] ranRunners;

    /// A runner of `BeanDefinitionOrderRunnerConfig` that records its name.
    final class NamedRunner : CommandLineRunner
    {
        private string name;

        /// The runner `name`.
        this(string name)
        {
            this.name = name;
        }

        /// Part of the upstream test fixture.
        void run(string[])
        {
            ranRunners ~= name;
        }
    }

    /// The `@Bean @Order(order)` definition of a `NamedRunner`, as Flint AOT generates it.
    private RootBeanDefinition orderedRunner(string name, int order, Object function(AotBeanFactory) @safe create)
    {
        import flint.boot : Runner;

        AotBeanDefinition record;
        record.name = name;
        record.type = typeNameOf!NamedRunner;
        record.types = [typeNameOf!NamedRunner, typeNameOf!CommandLineRunner, typeNameOf!Runner];
        record.order = order;
        record.create = create;
        return new RootBeanDefinition(record);
    }

    @("runCommandLineRunnersAndApplicationRunnersUsingOrderOnBeanDefinitions") unittest
    {
        import flint.core : Ordered;

        ranRunners = null;
        auto run = prepare();
        run.context.registrations ~= (TestContext context) {
            context.registerBeanDefinition("runnerC", orderedRunner("runnerC",
                    Ordered.LOWEST_PRECEDENCE, function Object(AotBeanFactory) => new NamedRunner("runnerC")));
            context.registerBeanDefinition("runnerB", orderedRunner("runnerB",
                    Ordered.LOWEST_PRECEDENCE - 1, function Object(AotBeanFactory) => new NamedRunner("runnerB")));
            context.registerBeanDefinition("runnerA", orderedRunner("runnerA",
                    Ordered.HIGHEST_PRECEDENCE, function Object(AotBeanFactory) => new NamedRunner("runnerA")));
        };
        run.start("arg");
        assert(ranRunners == ["runnerA", "runnerB", "runnerC"], ranRunners[0]);
    }
}

@("runnersAreCalledOnceWhenContextIsRefreshed") unittest
{
    auto run = prepare();
    const runner = registerCountingRunner(run);
    auto context = run.start();
    assert(context.isActive());
    assert(runner.calls == 1);
}

@("run") unittest
{
    auto context = FlintApplication.run!ExampleConfig(null);
    scope (exit)
        context.close();
    assert(context !is null);
}

@("commandLineArgsApplyToSpringApplication") unittest
{
    auto run = prepare();
    run.start("--flint.main.banner-mode=OFF");
    assert(!run.bannerPrinted(), run.output);
}

@("getApplicationArgumentsBean") unittest
{
    auto run = prepare();
    auto context = run.start("--debug", "spring", "boot");
    auto args = context.getBean!ApplicationArguments();
    assert(args.getNonOptionArgs() == ["spring", "boot"]);
    assert(args.containsOption("debug"));
}

@("nonWebApplicationConfiguredViaAPropertyHasTheCorrectTypeOfContextAndEnvironment") unittest
{
    import flint.boot : ApplicationEnvironment, KeepAliveApplicationContext;

    auto application = new FlintApplication(ClassRef("boot_tests.application_upstream_test.ExampleConfig"));
    application.setResourceReader(new MemoryReader(null));
    application.setEnvironmentVariables(null);
    application.setOutput((string) {});
    auto context = application.run(["--flint.main.web-application-type=none"]);
    scope (exit)
        context.close();
    // Flint's web server contexts are the ones that keep the process alive; the environment is Boot's own.
    assert(cast(KeepAliveApplicationContext) context is null);
    assert(cast(ApplicationEnvironment) context.getEnvironment() !is null);
}

@("failureResultsInSingleStackTrace") unittest
{
    import flint.beans.factory : BeanCreationException;
    import flint.java.lang : RuntimeException;
    import std.algorithm.searching : count;

    auto run = prepare();
    run.context.refreshFailure = new BeanCreationException("fail", "Bean creation failed",
            new RuntimeException("ExpectedError"));
    assertThrows!BeanCreationException(() { run.start(); });
    assert(run.output.count("Caused by: flint.java.lang.RuntimeException: ExpectedError") == 1, run.output);
}

version (FlintMainBeanFactoryDefaults)
{
    // Gap: Boot's defaults, no bean definition overriding and no circular references, are not applied.
    @("beanDefinitionOverridingIsDisabledByDefault") unittest
    {
        import flint.beans.factory.support : BeanDefinitionOverrideException;

        auto run = prepare();
        registerSomeBeans(run);
        assertThrows!BeanDefinitionOverrideException(() { run.start(); });
    }

    @("circularReferencesAreDisabledByDefault") unittest
    {
        import flint.beans.factory.support : DefaultListableBeanFactory;

        auto run = prepare();
        auto context = run.start("--flint.main.web-application-type=none");
        // Boot fails on the producer and consumer configurations' cycle: the factory refuses circular references.
        assert(!(cast(DefaultListableBeanFactory) context.getBeanFactory()).isAllowCircularReferences());
    }
}

@("beanDefinitionOverridingCanBeEnabled") unittest
{
    auto run = prepare();
    registerSomeBeans(run);
    auto context = run.start("--flint.main.allow-bean-definition-overriding=true",
            "--flint.main.web-application-type=none");
    assert(context.getBean!Text("someBean").value == "override");
}

@("circularReferencesCanBeEnabled") unittest
{
    import flint.beans.factory.support : DefaultListableBeanFactory;

    auto run = prepare();
    auto context = run.start("--flint.main.web-application-type=none", "--flint.main.allow-circular-references=true");
    assert((cast(DefaultListableBeanFactory) context.getBeanFactory()).isAllowCircularReferences());
}

@("relaxedBindingShouldWorkBeforeEnvironmentIsPrepared") unittest
{
    auto run = prepare(["resources/custom-config/application.yml": "hello: world\n"]);
    run.start("--flint.config.additionalLocation=classpath:custom-config/");
    assert(run.property("hello") == "world");
}

@("lazyInitializationIsDisabledByDefault") unittest
{
    auto run = prepare();
    registerCountedBeans(run, false);
    auto context = run.start("--flint.main.web-application-type=none");
    assert(context.getBean!Counter().value == 1);
}

version (FlintMainLazyInitialization)
{
    // Gap: `flint.main.lazy-initialization` and LazyInitializationExcludeFilter are not supported.
    @("lazyInitializationCanBeEnabled") unittest
    {
        auto run = prepare();
        registerCountedBeans(run, false);
        auto context = run.start("--flint.main.web-application-type=none", "--flint.main.lazy-initialization=true");
        assert(context.getBean!Counter().value == 0);
    }

    @("lazyInitializationIgnoresLazyInitializationExcludeFilteredBeans") unittest
    {
        import flint.boot : LazyInitializationExcludeFilter;

        auto run = prepare();
        run.context.registrations ~= (TestContext context) {
            auto counter = new Counter;
            context.registerBean!Counter("counter", () => counter);
            context.registerBean!CountedBean("notLazyBean", () => new CountedBean(counter));
            context.registerBean!LazyInitializationExcludeFilter("lazyInitializationExcludeFilter",
                    () => LazyInitializationExcludeFilter.forBeanTypes!CountedBean());
        };
        auto context = run.start("--flint.main.web-application-type=none", "--flint.main.lazy-initialization=true");
        assert(context.getBean!Counter().value == 1);
    }
}

@("lazyInitializationIgnoresBeansThatAreExplicitlyNotLazy") unittest
{
    auto run = prepare();
    registerCountedBeans(run, true);
    auto context = run.start("--flint.main.web-application-type=none", "--flint.main.lazy-initialization=true");
    assert(context.getBean!Counter().value == 1);
}

version (FlintPropertySourceAnnotation)
{
    // Gap: `@PropertySource` on a configuration class adds no property source.
    import flint.context.annotation : PropertySource;

    /// `PropertySourceConfig`.
    @PropertySource(null, ["classpath:spring-application-config-property-source.properties"])
    final class PropertySourceConfig
    {
    }

    @("movesConfigClassPropertySourcesToEnd") unittest
    {
        auto application = new FlintApplication(ClassRef("boot_tests.application_upstream_test.PropertySourceConfig"));
        auto context = new TestContext;
        application.setApplicationContextFactory(new TestFactory(context));
        enum file = "resources/spring-application-config-property-source.properties";
        application.setResourceReader(new MemoryReader([
            file: "test.name=spring-application-config-property-source\n"
        ]));
        application.setWebApplicationType(WebApplicationType.NONE);
        application.setOutput((string) {});
        application.setDefaultProperties(["test.name": "test"]);
        application.run(null);
        assert(context.getEnvironment().getProperty("test.name") == "spring-application-config-property-source");
    }
}

version (FlintApplicationEvents)
{
    // Gap: FlintApplication publishes none of Boot's application events (starting, environment prepared, context
    // initialized, prepared, started, ready, failed, exit code), and has no addListeners, run listeners,
    // SpringApplicationHook, afterRefresh hook or ApplicationStartup steps.
    import flint.boot : AbandonedRunException, ExitCodeEvent, ExitCodeGenerator,
        FlintApplicationHook, FlintApplicationRunListener;
    import flint.boot.availability : AvailabilityChangeEvent, LivenessState, ReadinessState;
    import flint.boot.context.event : ApplicationContextInitializedEvent,
        ApplicationEnvironmentPreparedEvent, ApplicationFailedEvent,
        ApplicationPreparedEvent, ApplicationReadyEvent,
        ApplicationStartedEvent, ApplicationStartingEvent, FlintApplicationEvent;
    import flint.context : ApplicationEvent, ApplicationListener, GenericApplicationListener;
    import flint.context.event : ContextRefreshedEvent;
    import flint.core.metrics : ApplicationStartup, StartupStep;

    /// The events a listener received, as the upstream Mockito listeners verify them.
    final class RecordingListener(E = ApplicationEvent) : ApplicationListener!E
    {
        /// Part of the upstream test fixture.
        ApplicationEvent[] events;
        /// Part of the upstream test fixture.
        Exception readyFailure;
        /// Part of the upstream test fixture.
        void delegate() @safe onEvent;

        override void onApplicationEvent(E event)
        {
            events ~= event;
            if (onEvent !is null)
                onEvent();
            if (readyFailure !is null && cast(ApplicationReadyEvent) event !is null)
                throw readyFailure;
        }

        /// Part of the upstream test fixture.
        bool received(T)()
        {
            foreach (event; events)
            {
                if (cast(T) event !is null)
                    return true;
            }
            return false;
        }

        /// The event types received, in order; availability changes as `Liveness.<state>` and `Readiness.<state>`.
        string[] kinds()
        {
            import std.conv : to;
            import flint.engine.aot.name : simpleTypeName;

            string[] result;
            foreach (event; events)
            {
                if (auto liveness = cast(AvailabilityChangeEvent!LivenessState) event)
                    result ~= "Liveness." ~ liveness.getState().to!string;
                else if (auto readiness = cast(AvailabilityChangeEvent!ReadinessState) event)
                    result ~= "Readiness." ~ readiness.getState().to!string;
                else
                    result ~= simpleTypeName(typeid(event).name);
            }
            return result;
        }
    }

    /// `ExitCodeListener`.
    final class ExitCodeListener : ApplicationListener!ExitCodeEvent
    {
        /// Part of the upstream test fixture.
        int exitCode = -1;

        override void onApplicationEvent(ExitCodeEvent event)
        {
            exitCode = event.getExitCode();
        }
    }

    /// `ExitStatusException`.
    final class ExitStatusException : Exception, ExitCodeGenerator
    {
        /// Part of the upstream test fixture.
        this()
        {
            super("ExitStatusException");
        }

        int getExitCode()
        {
            return 11;
        }
    }

    private static immutable string[] successEvents = [
        "ApplicationStartingEvent", "ApplicationEnvironmentPreparedEvent",
        "ApplicationContextInitializedEvent", "ApplicationPreparedEvent", "ContextRefreshedEvent",
        "ApplicationStartedEvent", "Liveness.CORRECT", "ApplicationReadyEvent",
        "Readiness.ACCEPTING_TRAFFIC"
    ];

    private static immutable string[] failedEvents = [
        "ApplicationStartingEvent", "ApplicationEnvironmentPreparedEvent",
        "ApplicationContextInitializedEvent", "ApplicationPreparedEvent", "ApplicationFailedEvent"
    ];

    @("applicationRunningEventListener") unittest
    {
        auto run = prepare();
        auto listener = new RecordingListener!ApplicationReadyEvent;
        run.application.addListeners(listener);
        run.start("--foo=bar");
        assert(listener.events.length == 1);
        assert((cast(ApplicationReadyEvent) listener.events[0]).getFlintApplication() is run.application);
    }

    @("contextRefreshedEventListener") unittest
    {
        auto run = prepare();
        auto listener = new RecordingListener!ContextRefreshedEvent;
        run.application.addListeners(listener);
        const context = run.start("--foo=bar");
        assert(listener.events.length == 1);
        assert((cast(ContextRefreshedEvent) listener.events[0]).getApplicationContext() is context);
        // Custom initializers do not switch off the defaults
        assert(run.property("foo") == "bar");
    }

    @("eventsArePublishedInExpectedOrder") unittest
    {
        auto run = prepare();
        auto listener = new RecordingListener!();
        run.application.addListeners(listener);
        run.start();
        assert(listener.kinds() == successEvents, listener.kinds()[0]);
    }

    @("applicationStartedEventHasStartedTime") unittest
    {
        auto run = prepare();
        auto listener = new RecordingListener!ApplicationStartedEvent;
        run.application.addListeners(listener);
        run.start();
        assert((cast(ApplicationStartedEvent) listener.events[0]).getTimeTaken() >= 0);
    }

    @("applicationReadyEventHasReadyTime") unittest
    {
        auto run = prepare();
        auto listener = new RecordingListener!ApplicationReadyEvent;
        run.application.addListeners(listener);
        run.start();
        assert((cast(ApplicationReadyEvent) listener.events[0]).getTimeTaken() >= 0);
    }

    @("runnersAreCalledAfterStartedIsLoggedAndBeforeApplicationReadyEventIsPublished") unittest
    {
        auto run = prepare();
        string[] calls;
        final class OrderedRunner : ApplicationRunner, CommandLineRunner
        {
            void run(ApplicationArguments)
            {
                assert(run.output.canFind("Started"));
                calls ~= "applicationRunner";
            }

            void run(string[])
            {
                assert(run.output.canFind("Started"));
                calls ~= "commandLineRunner";
            }
        }

        run.context.registrations ~= (TestContext context) {
            context.registerBean!OrderedRunner("runners", () => new OrderedRunner);
        };
        auto listener = new RecordingListener!ApplicationReadyEvent;
        listener.onEvent = () { calls ~= "ready"; };
        run.application.addListeners(listener);
        run.start();
        assert(calls == ["applicationRunner", "commandLineRunner", "ready"], calls[0]);
    }

    @("runnersAreNotCalledWhenContextIsClosedImmediatelyAfterRefresh") unittest
    {
        final class ClosingApplication : FlintApplication
        {
            this()
            {
                super(ClassRef("boot_tests.application_upstream_test.ExampleConfig"));
            }

            protected override void afterRefresh(ConfigurableApplicationContext context, ApplicationArguments)
            {
                context.close();
            }
        }

        auto run = prepare();
        auto application = new ClosingApplication;
        application.setApplicationContextFactory(new TestFactory(run.context));
        application.setResourceReader(new MemoryReader(null));
        application.setOutput((string) {});
        auto listener = new RecordingListener!FlintApplicationEvent;
        application.addListeners(listener);
        const runner = registerCountingRunner(run);
        auto context = application.run(null);
        assert(!context.isActive());
        assert(runner.calls == 0);
        assert(!listener.received!ApplicationStartedEvent);
        assert(!listener.received!ApplicationReadyEvent);
    }

    @("runnersAreNotCalledWhenContextIsClosedWhileHandlingApplicationStartedEvent") unittest
    {
        auto run = prepare();
        run.application.addListeners(GenericApplicationListener.forEventType!ApplicationStartedEvent(
                (ApplicationStartedEvent event) { event.getApplicationContext().close(); }));
        auto listener = new RecordingListener!FlintApplicationEvent;
        run.application.addListeners(listener);
        const runner = registerCountingRunner(run);
        auto context = run.start();
        assert(!context.isActive());
        assert(runner.calls == 0);
        assert(!listener.received!ApplicationReadyEvent);
    }

    /// A runner that fails with `failure`.
    final class FailingApplicationRunner : ApplicationRunner, CommandLineRunner
    {
        /// Part of the upstream test fixture.
        Exception failure;
        /// Part of the upstream test fixture.
        bool commandLine;

        /// Part of the upstream test fixture.
        this(Exception failure, bool commandLine)
        {
            this.failure = failure;
            this.commandLine = commandLine;
        }

        /// Part of the upstream test fixture.
        void run(ApplicationArguments)
        {
            if (!commandLine)
                throw failure;
        }

        /// Part of the upstream test fixture.
        void run(string[])
        {
            if (commandLine)
                throw failure;
        }
    }

    private void runnerFailurePublishesFailedEvent(bool commandLine)
    {
        import flint.java.lang : IllegalStateException;

        auto run = prepare();
        auto listener = new RecordingListener!FlintApplicationEvent;
        run.application.addListeners(listener);
        auto failure = new Exception("runner");
        run.context.registrations ~= (TestContext context) {
            context.registerBean!FailingApplicationRunner("runner",
                    () => new FailingApplicationRunner(failure, commandLine));
        };
        IllegalStateException thrown;
        try
            run.start();
        catch (IllegalStateException caught)
            thrown = caught;
        assert(thrown !is null && thrown.getCause() is failure);
        assert(listener.received!ApplicationStartedEvent);
        assert(listener.received!ApplicationFailedEvent);
        assert(!listener.received!ApplicationReadyEvent);
    }

    @("applicationRunnerFailureCausesApplicationFailedEventToBePublished") unittest
    {
        runnerFailurePublishesFailedEvent(false);
    }

    @("commandLineRunnerFailureCausesApplicationFailedEventToBePublished") unittest
    {
        runnerFailurePublishesFailedEvent(true);
    }

    @("failureInReadyEventListenerDoesNotCausePublicationOfFailedEvent") unittest
    {
        import flint.java.lang : RuntimeException;

        auto run = prepare();
        auto listener = new RecordingListener!FlintApplicationEvent;
        auto failure = new RuntimeException();
        listener.readyFailure = failure;
        run.application.addListeners(listener);
        RuntimeException thrown;
        try
            run.start();
        catch (RuntimeException caught)
            thrown = caught;
        assert(thrown is failure);
        assert(listener.received!ApplicationReadyEvent);
        assert(!listener.received!ApplicationFailedEvent);
    }

    private void failureInReadyEventListener(string expectedOutput)
    {
        auto run = prepare();
        auto exitCodeListener = new ExitCodeListener;
        run.application.addListeners(exitCodeListener);
        auto listener = new RecordingListener!FlintApplicationEvent;
        listener.readyFailure = new ExitStatusException;
        run.application.addListeners(listener);
        assertThrows!ExitStatusException(() { run.start(); });
        assert(listener.received!ApplicationReadyEvent);
        assert(!listener.received!ApplicationFailedEvent);
        assert(exitCodeListener.exitCode == 11);
        assert(run.output.canFind(expectedOutput), run.output);
    }

    @("failureInReadyEventListenerCloseApplicationContext") unittest
    {
        failureInReadyEventListener("Application run failed");
    }

    @("failureOnTheJvmLogsApplicationRunFailed") unittest
    {
        // Leading space only happens when logging
        failureInReadyEventListener(" Application run failed");
    }

    private void verifyRegisteredListenerSuccessEvents(ConfigurableApplicationContext context)
    {
        auto listener = context.getBean!(RecordingListener!())("testApplicationListener");
        assert(listener.kinds() == successEvents[4 .. $], listener.kinds()[0]);
    }

    private void registerListener(bool customMulticaster)
    {
        import flint.context.event : SimpleApplicationEventMulticaster;
        import flint.context.support : AbstractApplicationContext;

        auto run = prepare();
        run.context.registrations ~= (TestContext context) {
            context.registerBean!(RecordingListener!())("testApplicationListener", () => new RecordingListener!());
            if (customMulticaster)
                context.registerBean!SimpleApplicationEventMulticaster(
                        AbstractApplicationContext.APPLICATION_EVENT_MULTICASTER_BEAN_NAME,
                        () => new SimpleApplicationEventMulticaster);
        };
        auto listener = new RecordingListener!();
        run.application.addListeners(listener);
        auto context = run.start();
        assert(listener.received!ApplicationPreparedEvent);
        assert(listener.received!ContextRefreshedEvent);
        verifyRegisteredListenerSuccessEvents(context);
    }

    @("registerListener") unittest
    {
        registerListener(false);
    }

    @("registerListenerWithCustomMulticaster") unittest
    {
        registerListener(true);
    }

    /// `BrokenBeanFactoryPostProcessing` and `BrokenPostConstructConfig`: a refresh that fails before or after
    /// the context registered its listeners.
    private void breakRefresh(Run run, bool afterListenerRegistration)
    {
        import flint.beans.factory : BeanCreationException;
        import flint.context : ApplicationContextException;

        run.context.refreshFailure = afterListenerRegistration ? new BeanCreationException("thing",
                "Init method failed", null) : new ApplicationContextException("broken");
    }

    private void listenerFromApplication(bool afterListenerRegistration)
    {
        auto run = prepare();
        auto listener = new RecordingListener!();
        run.application.addListeners(listener);
        breakRefresh(run, afterListenerRegistration);
        assertThrows!Exception(() { run.start(); });
        assert(listener.kinds() == failedEvents, listener.kinds()[0]);
    }

    @("applicationListenerFromApplicationIsCalledWhenContextFailsRefreshBeforeListenerRegistration") unittest
    {
        listenerFromApplication(false);
    }

    @("applicationListenerFromApplicationIsCalledWhenContextFailsRefreshAfterListenerRegistration") unittest
    {
        listenerFromApplication(true);
    }

    private void listenerFromContext(bool afterListenerRegistration)
    {
        auto run = prepare();
        auto listener = new RecordingListener!();
        run.application.addInitializers((ConfigurableApplicationContext context) {
            context.addApplicationListener(listener);
        });
        breakRefresh(run, afterListenerRegistration);
        assertThrows!Exception(() { run.start(); });
        assert(listener.kinds() == ["ApplicationFailedEvent"], listener.kinds()[0]);
    }

    @("applicationListenerFromContextIsCalledWhenContextFailsRefreshBeforeListenerRegistration") unittest
    {
        listenerFromContext(false);
    }

    @("applicationListenerFromContextIsCalledWhenContextFailsRefreshAfterListenerRegistration") unittest
    {
        listenerFromContext(true);
    }

    /// A startup recording the steps it starts and ends.
    final class RecordingStartup : ApplicationStartup
    {
        /// Part of the upstream test fixture.
        string[] started;
        /// Part of the upstream test fixture.
        int ended;

        /// Part of the upstream test fixture.
        StartupStep start(string name)
        {
            started ~= name;
            return new RecordingStep(this);
        }
    }

    /// A step that counts its end on its startup.
    final class RecordingStep : StartupStep
    {
        /// Part of the upstream test fixture.
        RecordingStartup startup;

        /// Part of the upstream test fixture.
        this(RecordingStartup startup)
        {
            this.startup = startup;
        }

        /// Part of the upstream test fixture.
        void end()
        {
            startup.ended++;
        }
    }

    @("customApplicationStartupPublishStartupSteps") unittest
    {
        auto run = prepare();
        auto startup = new RecordingStartup;
        run.application.setApplicationStartup(startup);
        auto context = run.start();
        assert(context.getBean!ApplicationStartup() is startup);
        foreach (step; [
            "starting", "environment-prepared", "context-prepared", "context-loaded", "started",
            "ready"
        ])
            assert(startup.started.canFind("flint.boot.application." ~ step), step);
        assert(startup.started.length == startup.ended);
    }

    @("customApplicationStartupPublishStartupStepsWithFailure") unittest
    {
        auto run = prepare();
        auto startup = new RecordingStartup;
        run.application.setApplicationStartup(startup);
        breakRefresh(run, true);
        assertThrows!Exception(() { run.start(); });
        foreach (step; ["starting", "environment-prepared", "failed"])
            assert(startup.started.canFind("flint.boot.application." ~ step), step);
        assert(startup.started.length == startup.ended);
    }

    /// A run listener recording its calls.
    class RecordingRunListener : FlintApplicationRunListener
    {
        /// Part of the upstream test fixture.
        string[] calls;
        /// Part of the upstream test fixture.
        ConfigurableApplicationContext prepared;

        override void starting()
        {
            calls ~= "starting";
        }

        override void contextPrepared(ConfigurableApplicationContext context)
        {
            calls ~= "contextPrepared";
            prepared = context;
        }

        override void ready(ConfigurableApplicationContext context, long timeTaken)
        {
            calls ~= "ready";
        }

        override void failed(ConfigurableApplicationContext context, Throwable failure)
        {
            calls ~= "failed";
        }
    }

    @("withRunnableHookRunsWithHook") unittest
    {
        auto run = prepare();
        auto runListener = new RecordingRunListener;
        ConfigurableApplicationContext context;
        FlintApplication.withHook((FlintApplication) => runListener, () { context = run.start(); });
        assert(context !is null);
        assert(runListener.calls == ["starting", "contextPrepared", "ready"]);
        assert(runListener.prepared is context);
        assert(context.isRunning());
    }

    @("withCallableHookRunsWithHook") unittest
    {
        auto run = prepare();
        auto runListener = new RecordingRunListener;
        auto context = FlintApplication.withHook((FlintApplication) => runListener, () => run.start());
        assert(runListener.calls == ["starting", "contextPrepared", "ready"]);
        assert(runListener.prepared is context);
        assert(context.isRunning());
    }

    @("withHookWhenHookThrowsAbandonedRunExceptionAbandonsRun") unittest
    {
        final class AbandoningRunListener : RecordingRunListener
        {
            override void contextLoaded(ConfigurableApplicationContext context)
            {
                throw new AbandonedRunException(context);
            }
        }

        auto run = prepare();
        auto listener = new RecordingListener!();
        run.application.addListeners(listener);
        auto runListener = new AbandoningRunListener;
        AbandonedRunException abandoned;
        try
            FlintApplication.withHook((FlintApplication) => runListener, () => run.start());
        catch (AbandonedRunException caught)
            abandoned = caught;
        assert(abandoned !is null && abandoned.getApplicationContext() !is null);
        assert(!abandoned.getApplicationContext().isRunning());
        assert(runListener.calls == ["starting", "contextPrepared"]);
        assert(listener.received!ApplicationStartingEvent);
        assert(listener.received!ApplicationEnvironmentPreparedEvent);
        assert(listener.received!ApplicationPreparedEvent);
        assert(!listener.received!ApplicationReadyEvent);
        assert(!listener.received!ApplicationFailedEvent);
    }
}

version (FlintExitCodeExceptions)
{
    // Gap: a startup failure's exit code is not taken from an ExitCodeGenerator exception or an
    // ExitCodeExceptionMapper bean, and no ExitCodeEvent is published.
    import flint.boot : ExitCodeEvent, ExitCodeExceptionMapper, ExitCodeGenerator;
    import flint.context : ApplicationListener;
    import flint.java.lang : IllegalStateException;

    /// `ExitCodeListener`.
    final class ExitCodeRecorder : ApplicationListener!ExitCodeEvent
    {
        /// Part of the upstream test fixture.
        int exitCode = -1;

        override void onApplicationEvent(ExitCodeEvent event)
        {
            exitCode = event.getExitCode();
        }
    }

    /// `ExitStatusException`.
    final class ExitStatus : Exception, ExitCodeGenerator
    {
        /// Part of the upstream test fixture.
        this()
        {
            super("ExitStatusException");
        }

        int getExitCode()
        {
            return 11;
        }
    }

    /// The runner of `ExitCodeCommandLineRunConfig` and `MappedExitCodeCommandLineRunConfig`.
    final class ThrowingRunner : CommandLineRunner
    {
        /// Part of the upstream test fixture.
        bool withExitStatus;

        /// Part of the upstream test fixture.
        this(bool withExitStatus)
        {
            this.withExitStatus = withExitStatus;
        }

        /// Part of the upstream test fixture.
        void run(string[])
        {
            throw withExitStatus ? new IllegalStateException(new ExitStatus) : new IllegalStateException();
        }
    }

    /// `MappedExitCodeCommandLineRunConfig.exceptionMapper`.
    final class Mapper : ExitCodeExceptionMapper
    {
        int getExitCode(Throwable exception)
        {
            return cast(IllegalStateException) exception !is null ? 11 : 0;
        }
    }

    private void exitCodeFromException(bool mapped)
    {
        auto run = prepare();
        auto listener = new ExitCodeRecorder;
        run.application.addListeners(listener);
        run.context.registrations ~= (TestContext context) {
            context.registerBean!ThrowingRunner("runner", () => new ThrowingRunner(!mapped));
            if (mapped)
                context.registerBean!Mapper("exceptionMapper", () => new Mapper);
        };
        assertThrows!IllegalStateException(() { run.start(); });
        assert(run.application.getExitCodeOfLastFailure() == 11);
        assert(listener.exitCode == 11);
    }

    @("exitWithExplicitCodeFromException") unittest
    {
        exitCodeFromException(false);
    }

    @("exitWithExplicitCodeFromMappedException") unittest
    {
        exitCodeFromException(true);
    }
}

version (FlintApplicationInitializers)
{
    // Gap: FlintApplication has no ApplicationContextInitializers (setInitializers, addInitializers).
    import flint.boot : ApplicationContextInitializer;
    import flint.context : ApplicationContext;

    @("specificApplicationContextInitializer") unittest
    {
        auto run = prepare();
        ApplicationContext reference;
        run.application.setInitializers([
            ApplicationContextInitializer.of((ConfigurableApplicationContext context) {
                reference = context;
            })
        ]);
        const context = run.start("--foo=bar");
        assert(context is reference);
        // Custom initializers do not switch off the defaults
        assert(run.property("foo") == "bar");
    }

    @("runCommandLineRunnersAndApplicationRunnersWithParentContext") unittest
    {
        import flint.boot.builder : ParentContextApplicationContextInitializer;

        auto run = prepare();
        auto parent = new GenericApplicationContext;
        auto parentRunner = new CountingRunner;
        parent.registerBean!CountingRunner("runnerP", () => parentRunner);
        parent.refresh();
        run.application.addInitializers(new ParentContextApplicationContextInitializer(parent));
        const runner = registerCountingRunner(run);
        run.start("arg");
        assert(runner.calls == 1);
        assert(parentRunner.calls == 0);
    }

    @("beanDefinitionOverridingIsAppliedToInitializer") unittest
    {
        import flint.beans.factory.support : BeanDefinitionOverrideException;

        assertThrows!BeanDefinitionOverrideException(() {
            auto run = prepare();
            run.application.setInitializers([
                ApplicationContextInitializer.of((ConfigurableApplicationContext context) {
                    auto generic = cast(GenericApplicationContext) context;
                    generic.registerBean!Text("someBean", () => new Text("a"));
                    generic.registerBean!Text("someBean", () => new Text("b"));
                })
            ]);
            run.start();
        });
    }
}

version (FlintApplicationApi)
{
    // Gap: FlintApplication lacks these members of SpringApplication: setEnvironment (and the builder's
    // `environment`), setAddCommandLineProperties, getSources and getAllSources, a static run of several sources, and
    // `from`.
    import flint.boot.context.event : ApplicationEnvironmentPreparedEvent;
    import flint.context : GenericApplicationListener;
    import flint.core.env : MapPropertySource, StandardEnvironment;

    @("commandLinePropertySourceEnhancesEnvironment") unittest
    {
        import flint.core.env : CompositePropertySource;

        auto run = prepare();
        auto environment = new StandardEnvironment;
        environment.getPropertySources().addFirst(new MapPropertySource("commandLineArgs", [
            "foo": "original"
        ]));
        run.application.setEnvironment(environment);
        run.start("--foo=bar", "--bar=foo");
        assert(environment.getProperty("bar") == "foo");
        // New command line properties take precedence
        assert(environment.getProperty("foo") == "bar");
        auto composite = cast(CompositePropertySource) environment.getPropertySources().get("commandLineArgs");
        assert(composite !is null);
        assert(composite.getPropertySources().length == 2);
        assert(composite.getPropertySources()[0].getName() == "flintApplicationCommandLineArgs");
        assert(composite.getPropertySources()[1].getName() == "commandLineArgs");
    }

    @("disableCommandLinePropertySource") unittest
    {
        auto run = prepare();
        run.application.setAddCommandLineProperties(false);
        auto environment = new StandardEnvironment;
        run.application.setEnvironment(environment);
        run.start("--foo=bar");
        assert(environment.getPropertySources().get("commandLineArgs") is null);
    }

    @("defaultPropertiesShouldBeMerged") unittest
    {
        import flint.boot.builder : FlintApplicationBuilder;

        auto environment = new StandardEnvironment;
        environment.getPropertySources().addFirst(new MapPropertySource("defaultProperties", [
            "bar": "foo"
        ]));
        auto application = new FlintApplicationBuilder(ClassRef("boot_tests.application_upstream_test.ExampleConfig"))
            .environment(environment).properties("baz=bing").web(WebApplicationType.NONE).build();
        auto context = application.run(null);
        scope (exit)
            context.close();
        assert(context.getEnvironment().getProperty("bar") == "foo");
        assert(context.getEnvironment().getProperty("baz") == "bing");
    }

    @("loadSources") unittest
    {
        auto run = prepare();
        run.application.getSources() ~= "a";
        run.start();
        const all = run.application.getAllSources();
        assert(all.canFind("boot_tests.application_upstream_test.ExampleConfig"));
        assert(all.canFind("a"));
    }

    @("runComponents") unittest
    {
        auto context = FlintApplication.run([
            ClassRef("boot_tests.application_upstream_test.ExampleConfig"), ClassRef("object.Object")
        ], null);
        scope (exit)
            context.close();
        assert(context !is null);
    }

    /// `ExampleFromMainMethod.main`.
    private void exampleMain(string[] args)
    {
        auto application = new FlintApplication(ClassRef("boot_tests.application_upstream_test.ExampleConfig"));
        application.setWebApplicationType(WebApplicationType.NONE);
        application.run(args);
    }

    /// `ExampleAdditionalConfig`.
    final class ExampleAdditionalConfig
    {
        /// Part of the upstream test fixture.
        static bool created;

        /// Part of the upstream test fixture.
        this()
        {
            created = true;
        }
    }

    @("fromRunsWithAdditionalSources") unittest
    {
        assert(!ExampleAdditionalConfig.created);
        auto context = FlintApplication.from(&exampleMain).with_!ExampleAdditionalConfig().run()
            .getApplicationContext();
        scope (exit)
            context.close();
        assert(ExampleAdditionalConfig.created);
    }

    @("fromReturnsApplicationContext") unittest
    {
        auto context = FlintApplication.from(&exampleMain).with_!ExampleAdditionalConfig().run()
            .getApplicationContext();
        scope (exit)
            context.close();
        assert(context !is null);
    }

    /// `SingleUseAdditionalConfig`.
    final class SingleUseAdditionalConfig
    {
        /// Part of the upstream test fixture.
        static bool used;

        /// Part of the upstream test fixture.
        this()
        {
            import flint.java.lang : IllegalStateException;

            if (used)
                throw new IllegalStateException("Single-use configuration has already been used");
            used = true;
        }
    }

    /// `MultipleApplicationsMainMethod.main`: an inner application runs while the outer one prepares.
    private void multipleApplicationsMain(string[] args)
    {
        import flint.boot.builder : FlintApplicationBuilder;

        auto application = new FlintApplication(ClassRef("boot_tests.application_upstream_test.ExampleConfig"));
        application.setWebApplicationType(WebApplicationType.NONE);
        application.addListeners(GenericApplicationListener.forEventType!ApplicationEnvironmentPreparedEvent(
                (ApplicationEnvironmentPreparedEvent) {
                auto builder = new FlintApplicationBuilder(ClassRef("object.Object"));
                builder.web(WebApplicationType.NONE);
                builder.run().close();
            }));
        application.run(args);
    }

    @("fromWithMultipleApplicationsOnlyAppliesAdditionalSourcesOnce") unittest
    {
        auto context = FlintApplication.from(&multipleApplicationsMain)
            .with_!SingleUseAdditionalConfig().run().getApplicationContext();
        scope (exit)
            context.close();
        assert(context.getBean!SingleUseAdditionalConfig() !is null);
    }

    /// `Example` of `ProfileConfig`.
    final class Example
    {
    }

    @("fromAppliesProfiles") unittest
    {
        auto context = FlintApplication.from(&exampleMain).with_!ExampleConfig()
            .withAdditionalProfiles("custom").run().getApplicationContext();
        scope (exit)
            context.close();
        assert(context.getBeanProvider!Example().getIfAvailable() !is null);
    }
}

version (FlintBootstrapRegistry)
{
    // Gap: there is no BootstrapRegistry, so no addBootstrapRegistryInitializer.
    import flint.boot.bootstrap : BootstrapContextClosedEvent, BootstrapRegistry, InstanceSupplier;

    @("addBootstrapRegistryInitializer") unittest
    {
        import flint.boot.context.event : ApplicationEnvironmentPreparedEvent, ApplicationStartingEvent;
        import flint.context : ApplicationEvent, ApplicationListener;

        final class Listener : ApplicationListener!ApplicationEvent
        {
            ApplicationStartingEvent starting;
            ApplicationEnvironmentPreparedEvent prepared;

            override void onApplicationEvent(ApplicationEvent event)
            {
                if (auto e = cast(ApplicationStartingEvent) event)
                    starting = e;
                if (auto e = cast(ApplicationEnvironmentPreparedEvent) event)
                    prepared = e;
            }
        }

        auto run = prepare();
        run.application.addBootstrapRegistryInitializer((BootstrapRegistry registry) {
            registry.register!Text(InstanceSupplier!Text.of(new Text("boot")));
        });
        auto listener = new Listener;
        run.application.addListeners(listener);
        run.start();
        assert(listener.starting.getBootstrapContext().get!Text().value == "boot");
        assert(listener.prepared.getBootstrapContext().get!Text().value == "boot");
    }

    @("addBootstrapRegistryInitializerCanRegisterBeans") unittest
    {
        auto run = prepare();
        run.application.addBootstrapRegistryInitializer((BootstrapRegistry registry) {
            registry.register!Text(InstanceSupplier!Text.of(new Text("boot")));
            registry.addCloseListener((BootstrapContextClosedEvent event) {
                auto text = event.getBootstrapContext().get!Text();
                assert(text !is null);
                event.getApplicationContext().getBeanFactory().registerSingleton("test", text);
            });
        });
        auto context = run.start();
        assert(context.getBean!Text("test").value == "boot");
    }
}

version (FlintEnvironmentPrefix)
{
    // Gap: there is no environment prefix (`setEnvironmentPrefix`, `flint.main.environment-prefix`).
    @("settingEnvironmentPrefixViaPropertiesThrowsException") unittest
    {
        import flint.java.lang : IllegalStateException;

        auto run = prepare();
        assertThrows!IllegalStateException(() { run.start("--flint.main.environment-prefix=my"); });
    }

    @("bindsEnvironmentPrefixToSpringApplication") unittest
    {
        auto run = prepare();
        run.application.setEnvironmentPrefix("my");
        run.start();
        assert(run.application.getEnvironmentPrefix() == "my");
    }
}

// ---- ResourceBannerTests ------------------------------------------------------------------------------------

version (FlintResourceBannerPropertyResolvers)
{
    // Gap: ResourceBanner has no getPropertyResolvers hook to add a resolver.
    import flint.boot : ApplicationEnvironment, ResourceBanner;
    import flint.core.env : PropertyResolver;

    /// `MutatingResourceBanner`: adds a resolver answering `foo` with `bar`.
    final class MutatingResourceBanner : ResourceBanner
    {
        /// Part of the upstream test fixture.
        this(string text)
        {
            super(text);
        }

        protected override string getBootVersion()
        {
            return "1";
        }

        protected override PropertyResolver[] getPropertyResolvers(ApplicationEnvironment environment,
                string sourceClass)
        {
            import flint.boot.context.properties.source : MapConfigurationPropertySource;

            return super.getPropertyResolvers(environment,
                    sourceClass) ~ new MapConfigurationPropertySource("foo", [["foo", "bar"]]);
        }
    }

    @("renderWithMutation") unittest
    {
        import flint.boot.context.config : ConfigDataResult, Profiles;
        import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
        import std.algorithm.searching : startsWith;

        auto environment = new ApplicationEnvironment(new ConfigDataResult(
                [
                cast(ConfigurationPropertySource) new MapConfigurationPropertySource("map",
                [["flint.application.version", "2"], ["a", "1"]])
        ], new Profiles(null, ["default"])));
        string banner;
        new MutatingResourceBanner("banner ${foo}").printBanner(environment, null, (string s) {
            banner ~= s;
        });
        assert(banner.startsWith("banner bar"), banner);
    }
}

// ---- StartupInfoLoggerTests ---------------------------------------------------------------------------------

private string startedBy()
{
    import std.file : getcwd;
    import std.process : environment;

    return " started by " ~ environment.get("USER", environment.get("USERNAME", "unknown")) ~ " in " ~ getcwd() ~ ")";
}

private Run startupInfo(string version_)
{
    auto run = prepare();
    run.application.setDefaultProperties(["flint.application.version": version_]);
    run.start();
    return run;
}

@("startingFormat") unittest
{
    import flint.boot.internal.log : processId;
    import std.conv : to;

    auto run = startupInfo("1.2.3");
    const expected = "Starting ExampleConfig v1.2.3 using Flint " ~ FlintBootVersion.getVersion()
        ~ " with PID " ~ processId().to!string ~ " (";
    assert(run.output.canFind(expected), run.output);
    assert(run.output.canFind(startedBy()), run.output);
}

@("startingFormatWhenVersionIsNotAvailable") unittest
{
    import flint.boot.internal.log : processId;
    import std.conv : to;

    auto run = startupInfo("");
    const expected = "Starting ExampleConfig using Flint " ~ FlintBootVersion.getVersion()
        ~ " with PID " ~ processId().to!string ~ " (";
    assert(run.output.canFind(expected), run.output);
    assert(run.output.canFind(startedBy()), run.output);
}

version (FlintProcessUptime)
{
    // Gap: the process uptime is read from /proc, so macOS and Windows report "process running for 0.0".
    @("startedFormat") unittest
    {
        import std.conv : to;
        import std.regex : matchFirst, regex;

        auto run = startupInfo("1.2.3");
        auto match = matchFirst(run.output,
                regex(`Started ExampleConfig in (\d+\.\d{1,3}) seconds \(process running for (\d+\.\d{1,3})\)`));
        assert(!match.empty, run.output);
        assert(match[2].to!double > 0 && match[2].to!double >= match[1].to!double, match[0]);
    }
}

// ---- SpringApplicationBannerPrinterTests --------------------------------------------------------------------

@("shouldUseUtf8") unittest
{
    auto run = prepare(["resources/banner.txt": "\U0001F60D Spring Boot! \U0001F60D"]);
    run.application.setBannerMode(Banner.Mode.LOG);
    run.start();
    assert(run.output.canFind("\U0001F60D Spring Boot! \U0001F60D"), run.output);
}

// ---- SpringBootVersionTests ---------------------------------------------------------------------------------

@("getVersionShouldReturnVersionMatchingGradleProperties") unittest
{
    import std.file : exists, getcwd, readText;
    import std.json : parseJSON;
    import std.path : buildPath, dirName;

    // Flint's release is flint-dependencies.json's, as Boot's is gradle.properties' `version`.
    string directory = getcwd();
    while (!buildPath(directory, "flint-dependencies.json").exists && directory.dirName != directory)
        directory = directory.dirName;
    const json = parseJSON(readText(buildPath(directory, "flint-dependencies.json")));
    assert(FlintBootVersion.getVersion() == json["release"].str);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
