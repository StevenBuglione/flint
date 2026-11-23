// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/SpringApplicationTests.java
// with DefaultApplicationArgumentsTests.java, ResourceBannerTests.java and StartupInfoLoggerTests.java from the same
// directory, and diagnostics/analyzer/BindFailureAnalyzerTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the application context is a stub of the context contract (framework-core's
// context lands separately); output is captured through `setOutput` instead of Boot's OutputCaptureExtension.
module boot_tests.application_test;

import boot_tests.support : assertThrows;
import flint.boot : ApplicationArguments, ApplicationContextFactory, ApplicationEnvironment,
    ApplicationRunner, Banner, ClassRef, CommandLineRunner,
    DefaultApplicationArguments,
    ExitCodeGenerator, FlintApplication, FlintBootBanner, ResourceBanner, WebApplicationType;
import flint.boot.context.config : ConfigDataResourceReader, ConfigDataResult, Profiles;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.internal.context : ConfigurableApplicationContext;
import flint.engine.aot.any : Any;
import flint.engine.aot.bean : BeanFactory;

@safe:

// ---- a stub context -----------------------------------------------------------------------------------------

private final class StubBeanFactory : BeanFactory
{
    Object[] beans;

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

    Object[] getBeansOfType(string type)
    {
        import flint.boot : Runner;

        Object[] result;
        foreach (bean; beans)
        {
            if ((type == "flint.boot.Runner" && cast(Runner) bean !is null)
                    || (type == "flint.boot.ExitCodeGenerator" && cast(ExitCodeGenerator) bean !is null))
                result ~= bean;
        }
        return result;
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

private final class StubContext : ConfigurableApplicationContext
{
    StubBeanFactory factory;
    string[] events;
    Object environment;
    Object[string] singletons;
    bool active;
    Exception refreshFailure;

    this()
    {
        factory = new StubBeanFactory;
    }

    string getId()
    {
        return "application";
    }

    void setEnvironment(Object environment)
    {
        this.environment = environment;
    }

    void registerSingleton(string name, Object singleton)
    {
        singletons[name] = singleton;
    }

    void refresh()
    {
        events ~= "refresh";
        if (refreshFailure !is null)
            throw refreshFailure;
        active = true;
    }

    BeanFactory getBeanFactory()
    {
        return factory;
    }

    bool isActive()
    {
        return active;
    }

    void close()
    {
        events ~= "close";
        active = false;
    }

    void awaitTermination()
    {
    }
}

private final class StubFactory : ApplicationContextFactory
{
    StubContext context;
    WebApplicationType requested;

    this(StubContext context)
    {
        this.context = context;
    }

    ConfigurableApplicationContext create(WebApplicationType webApplicationType)
    {
        requested = webApplicationType;
        return context;
    }
}

private final class MemoryReader : ConfigDataResourceReader
{
    string[string] files;

    this(string[string] files)
    {
        this.files = files;
    }

    const(ubyte)[] read(string path)
    {
        if (auto content = path in files)
            return cast(const(ubyte)[])*content;
        return null;
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

/// The application class of the tests.
final class ExampleConfig
{
}

private struct Run
{
    FlintApplication application;
    StubContext context;
    StubFactory factory;
    string output;
}

private Run prepare(string[string] files = null, string[string] environment = null)
{
    Run run;
    run.context = new StubContext;
    run.factory = new StubFactory(run.context);
    run.application = new FlintApplication(ClassRef("boot_tests.application_test.ExampleConfig"));
    run.application.setApplicationContextFactory(run.factory);
    run.application.setResourceReader(new MemoryReader(files));
    run.application.setEnvironmentVariables(environment);
    return run;
}

private string capture(ref Run run, string[] args = null)
{
    string output;
    run.application.setOutput((string text) { output ~= text; });
    run.application.run(args);
    return output;
}

// ---- SpringApplicationTests --------------------------------------------------------------------------------

@("customBanner") unittest
{
    auto run = prepare(["resources/banner.txt": "Running a Test!\n"]);
    const output = capture(run);
    assert(output.length >= 15 && output[0 .. 15] == "Running a Test!", output);
}

@("bannerModeOff") unittest
{
    auto run = prepare();
    run.application.setBannerMode(Banner.Mode.OFF);
    import std.algorithm.searching : canFind;

    assert(!capture(run).canFind("Flint Boot"));
}

@("bannerModeOffViaProperty") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare(["resources/application.properties": "flint.main.banner-mode=off\n"]);
    assert(!capture(run).canFind(":: Flint Boot ::"));
}

@("defaultBannerShowsFlintBootVersion") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    const output = capture(run);
    assert(output.canFind(" :: Flint Boot ::                 (v0.7.0)"), output);
}

@("logsActiveProfilesWithoutProfileAndSingleDefault") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    assert(capture(run).canFind("No active profile set, falling back to 1 default profile: \"default\""));
}

@("logsActiveProfilesWithSingleProfile") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    assert(capture(run, ["--flint.profiles.active=myprofiles"])
            .canFind("The following 1 profile is active: \"myprofiles\""));
}

@("logsActiveProfilesWithMultipleProfiles") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    run.application.setAdditionalProfiles("p1", "p2");
    assert(capture(run).canFind("The following 2 profiles are active: \"p1\", \"p2\""));
}

@("disableLogStartupInfo") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    run.application.setLogStartupInfo(false);
    assert(!capture(run).canFind("Started "));
}

@("logsStartedLine") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    const output = capture(run);
    assert(output.canFind("Starting ExampleConfig using Flint 0.7.0 with PID "), output);
    assert(output.canFind("Started ExampleConfig in "), output);
    assert(output.canFind(" seconds (process running for "), output);
}

@("specificWebApplicationType") unittest
{
    auto run = prepare();
    run.application.setWebApplicationType(WebApplicationType.SERVLET);
    capture(run);
    assert(run.factory.requested == WebApplicationType.SERVLET);
}

@("specificWebApplicationTypeViaProperty") unittest
{
    auto run = prepare([
        "resources/application.yaml": "flint:\n  main:\n    web-application-type: reactive\n"
    ]);
    capture(run);
    assert(run.factory.requested == WebApplicationType.REACTIVE);
}

@("commandLinePropertySource") unittest
{
    auto run = prepare();
    capture(run, ["--foo=bar"]);
    auto environment = cast(ApplicationEnvironment) run.context.environment;
    assert(environment.getProperty("foo") == "bar");
}

@("defaultCommandLineArgs") unittest
{
    auto run = prepare();
    run.application.setDefaultProperties(["baz": "", "bar": "foo"]);
    capture(run, ["--bar=spam", "bucket"]);
    auto environment = cast(ApplicationEnvironment) run.context.environment;
    assert(environment.getProperty("bar") == "spam");
    assert(environment.getProperty("baz") == "");
}

@("registersArgumentsAndBannerAsSingletons") unittest
{
    auto run = prepare();
    capture(run, ["--debug", "spring"]);
    auto arguments = cast(ApplicationArguments) run.context.singletons["flintApplicationArguments"];
    assert(arguments.getNonOptionArgs() == ["spring"]);
    assert(cast(Banner) run.context.singletons["flintBootBanner"]!is null);
}

private final class OrderRecorder
{
    string[] calls;
}

private final class TestCommandLineRunner : CommandLineRunner
{
    OrderRecorder recorder;
    string[] seen;

    this(OrderRecorder recorder)
    {
        this.recorder = recorder;
    }

    void run(string[] args)
    {
        recorder.calls ~= "command";
        seen = args;
    }
}

private final class TestApplicationRunner : ApplicationRunner
{
    OrderRecorder recorder;
    bool debugOption;

    this(OrderRecorder recorder)
    {
        this.recorder = recorder;
    }

    void run(ApplicationArguments args)
    {
        recorder.calls ~= "application";
        debugOption = args.containsOption("debug");
    }
}

@("runCommandLineRunnersAndApplicationRunners") unittest
{
    auto run = prepare();
    auto recorder = new OrderRecorder;
    auto commandLine = new TestCommandLineRunner(recorder);
    auto application = new TestApplicationRunner(recorder);
    run.context.factory.beans = [commandLine, application];
    capture(run, ["--debug", "arg"]);
    assert(recorder.calls == ["command", "application"]);
    assert(commandLine.seen == ["--debug", "arg"]);
    assert(application.debugOption);
}

private final class FailingRunner : CommandLineRunner
{
    void run(string[])
    {
        throw new Exception("runner failed");
    }
}

@("failureInRunnerClosesContextAndRethrows") unittest
{
    import std.algorithm.searching : canFind;

    auto run = prepare();
    run.context.factory.beans = [new FailingRunner];
    string output;
    run.application.setOutput((string text) { output ~= text; });
    assertThrows!Exception(() { run.application.run(null); }, "runner failed");
    assert(run.context.events == ["refresh", "close"]);
    assert(output.canFind("Application run failed"), output);
}

@("failureAnalysisIsReportedForBindFailure") unittest
{
    import flint.boot.context.properties.bind : BindException, Binder;
    import std.algorithm.searching : canFind;

    auto run = prepare(["resources/application.properties": "test.foo=bar\n"]);
    run.context.refreshFailure = new Exception("refresh");
    // A refresh that fails with a BindException is explained by BindFailureAnalyzer.
    auto source = new MapConfigurationPropertySource("test", [["test.foo", "bar"]]);
    try
        new Binder([cast(ConfigurationPropertySource) source]).bind!int("test.foo");
    catch (BindException failure)
        run.context.refreshFailure = failure;
    string output;
    run.application.setOutput((string text) { output ~= text; });
    assertThrows!BindException(() { run.application.run(null); });
    assert(output.canFind("APPLICATION FAILED TO START"), output);
    assert(output.canFind("Failed to bind properties under 'test.foo' to int:"), output);
    assert(output.canFind("    Property: test.foo"), output);
    assert(output.canFind("    Value: \"bar\""), output);
    assert(output.canFind("    Reason: failed to convert java.lang.String to int"), output);
    assert(output.canFind("Action:\n\nUpdate your application's configuration"), output);
}

private final class FixedExitCode : ExitCodeGenerator
{
    int code;

    this(int code)
    {
        this.code = code;
    }

    int getExitCode()
    {
        return code;
    }
}

@("exit") unittest
{
    auto run = prepare();
    capture(run);
    assert(FlintApplication.exit(run.context) == 0);
    assert(!run.context.isActive());
}

@("exitWithExplicitCode") unittest
{
    auto run = prepare();
    capture(run);
    assert(FlintApplication.exit(run.context, new FixedExitCode(2)) == 2);
}

@("exitWithExplicitCodeFromBean") unittest
{
    auto run = prepare();
    run.context.factory.beans = [new FixedExitCode(2)];
    capture(run);
    assert(FlintApplication.exit(run.context) == 2);
}

@("noApplicationContextFactoryFails") unittest
{
    import flint.java.lang : IllegalStateException;

    auto application = new FlintApplication(ClassRef("x.App"));
    application.setResourceReader(new MemoryReader(null));
    application.setEnvironmentVariables(null);
    application.setOutput((string) {});
    assertThrows!IllegalStateException(() { application.run(null); }, "No ApplicationContextFactory");
}

// ---- DefaultApplicationArgumentsTests -----------------------------------------------------------------------

private enum string[] ARGS = ["--foo=bar", "--foo=baz", "--debug", "spring", "boot"];

@("getArgs") unittest
{
    assert(new DefaultApplicationArguments(ARGS).getSourceArgs() == ARGS);
}

@("optionNames") unittest
{
    assert(new DefaultApplicationArguments(ARGS).getOptionNames() == ["foo", "debug"]);
}

@("containsOption") unittest
{
    auto arguments = new DefaultApplicationArguments(ARGS);
    assert(arguments.containsOption("foo"));
    assert(arguments.containsOption("debug"));
    assert(!arguments.containsOption("spring"));
}

@("getOptionValues") unittest
{
    auto arguments = new DefaultApplicationArguments(ARGS);
    assert(arguments.getOptionValues("foo") == ["bar", "baz"]);
    assert(arguments.getOptionValues("debug").length == 0 && arguments.getOptionValues("debug") !is null);
    assert(arguments.getOptionValues("spring") is null);
}

@("getNonOptionArgs") unittest
{
    assert(new DefaultApplicationArguments(ARGS).getNonOptionArgs() == ["spring", "boot"]);
}

@("getNoNonOptionArgs") unittest
{
    assert(new DefaultApplicationArguments("--debug").getNonOptionArgs().length == 0);
}

// ---- ResourceBannerTests -----------------------------------------------------------------------------------

private final class MockResourceBanner : ResourceBanner
{
    private string bootVersion;
    private string title;

    this(string text, string bootVersion, string title)
    {
        super(text);
        this.bootVersion = bootVersion;
        this.title = title;
    }

    protected override string getBootVersion()
    {
        return bootVersion;
    }

    protected override string getApplicationTitle(string sourceClass)
    {
        return title;
    }
}

private string printBanner(string text, string bootVersion, string applicationVersion,
        string title, string ansi = "never")
{
    string[2][] entries = [["a", "1"], ["flint.output.ansi.enabled", ansi]];
    if (applicationVersion !is null)
        entries ~= ["spring.application.version", applicationVersion];
    auto environment = new ApplicationEnvironment(new ConfigDataResult(
            [cast(ConfigurationPropertySource) new MapConfigurationPropertySource("map",
            entries)], new Profiles(null, ["default"])));
    string output;
    new MockResourceBanner(text, bootVersion, title).printBanner(environment, "ExampleConfig", (string s) {
        output ~= s;
    });
    return output;
}

private bool startsWith(string text, string prefix) pure
{
    return text.length >= prefix.length && text[0 .. prefix.length] == prefix;
}

@("renderVersions") unittest
{
    assert(printBanner("banner ${a} ${spring-boot.version} ${application.version}", "10.2", "2.0",
            null).startsWith("banner 1 10.2 2.0"));
}

@("renderWithoutVersions") unittest
{
    assert(printBanner("banner ${a} ${spring-boot.version} ${application.version}", null, null,
            null).startsWith("banner 1  "));
}

@("renderWithoutVersionsWithDefaultValues") unittest
{
    assert(printBanner("banner ${a} ${spring-boot.version:X.Y.Z} ${application.version:A.B.C}",
            null, null, null).startsWith("banner 1 X.Y.Z A.B.C"));
}

@("renderFormattedVersions") unittest
{
    assert(printBanner("banner ${a}${spring-boot.formatted-version}${application.formatted-version}",
            "10.2", "2.0", null).startsWith("banner 1 (v10.2) (v2.0)"));
}

@("renderWithoutFormattedVersions") unittest
{
    assert(printBanner("banner ${a} ${spring-boot.formatted-version} ${application.formatted-version}",
            null, null, null).startsWith("banner 1  "));
}

@("renderWithoutFormattedVersionsWithDefaultValues") unittest
{
    assert(printBanner(
            "banner ${a} ${spring-boot.formatted-version:(vX.Y.Z)} ${application.formatted-version:(vA.B.C)}",
            null, null, null).startsWith("banner 1 (vX.Y.Z) (vA.B.C)"));
}

@("renderWithColors") unittest
{
    const banner = printBanner("${Ansi.RED}This is red.${Ansi.NORMAL}", null, null, null, "always");
    assert(banner.startsWith("\x1b[31mThis is red.\x1b[0m"), banner);
}

@("renderWithColorsButDisabled") unittest
{
    assert(printBanner("${Ansi.RED}This is red.${Ansi.NORMAL}", null, null, null, "never").startsWith("This is red."));
}

@("renderWith256Colors") unittest
{
    const banner = printBanner("${AnsiColor.208}This is orange.${Ansi.NORMAL}", null, null, null, "always");
    assert(banner.startsWith("\x1b[38;5;208mThis is orange.\x1b[0m"), banner);
}

@("renderWith256ColorsButDisabled") unittest
{
    assert(printBanner("${AnsiColor.208}This is orange.${Ansi.NORMAL}", null, null, null, "never")
            .startsWith("This is orange."));
}

@("renderWithTitle") unittest
{
    assert(printBanner("banner ${application.title} ${a}", null, null, "title").startsWith("banner title 1"));
}

@("renderWithoutTitle") unittest
{
    assert(printBanner("banner ${application.title} ${a}", null, null, null).startsWith("banner  1"));
}

@("renderWithoutTitleWithDefaultValue") unittest
{
    assert(printBanner("banner ${application.title:Default Title} ${a}", null, null, null)
            .startsWith("banner Default Title 1"));
}

@("renderWithDefaultValues") unittest
{
    assert(printBanner("banner ${a:default-a} ${b:default-b} ${spring-boot.version:default-boot-version} "
            ~ "${application.version:default-application-version}",
            "10.2", "1.0", null).startsWith("banner 1 default-b 10.2 1.0"));
}

@("flint.defaultBanner") unittest
{
    auto environment = new ApplicationEnvironment(
            new ConfigDataResult([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("map",
            [["flint.output.ansi.enabled", "never"]])
    ], new Profiles(null, ["default"])));
    string output;
    new FlintBootBanner().printBanner(environment, null, (string s) { output ~= s; });
    import std.algorithm.searching : canFind;

    assert(output.canFind("|_|   |_|_|_| |_|\\__|\n\n :: Flint Boot ::                 (v0.7.0)\n"), output);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
