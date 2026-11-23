// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/SpringApplication.java
// with ApplicationArguments.java, DefaultApplicationArguments.java, CommandLineRunner.java, ApplicationRunner.java,
// Runner.java, Banner.java, SpringBootBanner.java, ResourceBanner.java, SpringApplicationBannerPrinter.java,
// StartupInfoLogger.java, ExitCodeGenerator.java, WebApplicationType.java, SpringBootVersion.java,
// SpringBootConfiguration.java and ApplicationContextFactory.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: "Spring" becomes "Flint" in names and keys (ADR-030); `Class<?>` sources are
// `ClassRef`s or template parameters (rulebook R4); the entry point is `mixin FlintMain!App` (deviation D-1); the
// banner is Flint's own art; Java-only facilities (class loaders, `spring.factories`, AOT detection) are absent.

/// `org.springframework.boot`: bootstrapping an application with `FlintApplication`.
///
/// ```d
/// @FlintBootApplication
/// class RestServiceApplication
/// {
/// }
///
/// mixin FlintMain!RestServiceApplication;   // deviation D-1: D's entry point is a free function
/// ```
///
/// `FlintApplication.run!App(args)` works as `SpringApplication.run(App.class, args)` does. It loads the
/// configuration (command line, environment, `application.{properties,yaml}`, profiles), prints the banner and logs
/// the startup info. It then creates and refreshes the application context, logs "Started ... in ... seconds", and
/// calls the `ApplicationRunner` and `CommandLineRunner` beans. A startup failure is explained by the failure
/// analyzers ("APPLICATION FAILED TO START").
module flint.boot;

import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions,
    ConfigDataResourceReader, ConfigDataResult, Profiles;
import flint.boot.context.properties.source : ConfigurationPropertyName,
    ConfigurationPropertySource, ConfigurationPropertySources, MapConfigurationPropertySource;
import flint.boot.diagnostics : FailureAnalysisReporter, FailureAnalyzer, FailureAnalyzers,
    LoggingFailureAnalysisReporter;
import flint.boot.internal.context : ConfigurableApplicationContext;
import flint.boot.internal.core_env : CommandLineArgs, parseCommandLine;
import flint.boot.internal.lang : IllegalArgumentException, IllegalStateException;
import flint.boot.internal.log : Log, LogSettings;
import flint.boot.logging : LogLevel;

public import flint.boot.context.properties : ClassRef;

@safe:

/// Flint Boot's version.
struct FlintBootVersion
{
    /// The version string, as `${flint-boot.version}` prints it.
    static string getVersion() pure nothrow @nogc
    {
        return "0.7.0";
    }
}

/// The arguments an application was run with.
interface ApplicationArguments
{
    /// The raw arguments, as passed to `run` (without the program name).
    const(string)[] getSourceArgs();

    /// The names of the option arguments (`--name=value`, `--name`).
    const(string)[] getOptionNames();

    /// Whether `name` was given as an option.
    bool containsOption(string name);

    /// The values of the option `name`: empty for `--name` without a value, `null` when it was not given.
    const(string)[] getOptionValues(string name);

    /// The non-option arguments.
    const(string)[] getNonOptionArgs();
}

/// The default `ApplicationArguments`, parsed as spring-core's `SimpleCommandLinePropertySource` does.
final class DefaultApplicationArguments : ApplicationArguments
{
    private string[] args;
    private CommandLineArgs parsed;

    /// Parse `args`.
    this(string[] args...)
    {
        if (args is null)
            args = [];
        this.args = args.dup;
        this.parsed = parseCommandLine(this.args);
    }

    const(string)[] getSourceArgs()
    {
        return args;
    }

    const(string)[] getOptionNames()
    {
        return parsed.getOptionNames();
    }

    /// Whether `name` was given as an option.
    bool containsOption(string name)
    {
        return parsed.containsOption(name);
    }

    const(string)[] getOptionValues(string name)
    {
        return parsed.getOptionValues(name);
    }

    const(string)[] getNonOptionArgs()
    {
        return parsed.getNonOptionArgs();
    }
}

/// Marks the runner interfaces.
interface Runner
{
}

/// A bean run once the context has started, with the raw arguments. Throwing aborts startup, as Java's
/// `throws Exception` does.
interface CommandLineRunner : Runner
{
    /// Run.
    void run(string[] args);
}

/// A bean run once the context has started, with the parsed arguments.
interface ApplicationRunner : Runner
{
    /// Run.
    void run(ApplicationArguments args);
}

/// A bean that supplies the exit code `FlintApplication.exit` returns.
interface ExitCodeGenerator
{
    /// The exit code.
    int getExitCode();
}

/// The kind of web application a context runs.
enum WebApplicationType
{
    /// Not a web application: no embedded server.
    NONE,
    /// A servlet-based web application with an embedded server.
    SERVLET,
    /// A reactive web application.
    REACTIVE
}

/// Marks the application's `@Configuration` class; `@FlintBootApplication` carries it.
struct FlintBootConfiguration
{
    /// Whether `@Bean` methods are proxied to enforce singleton semantics.
    bool proxyBeanMethods = true;
}

/// The environment Boot prepares: property sources in precedence order, and the profiles.
///
/// It stands in for spring-core's `StandardEnvironment` (Boot's `ApplicationEnvironment` extends it) until
/// `flint.core.env` lands, and keeps its method names.
final class ApplicationEnvironment
{
    private ConfigDataResult data;

    /// The environment of loaded config data.
    this(ConfigDataResult data) pure nothrow @nogc
    {
        this.data = data;
    }

    /// The value of `key`, with placeholders resolved, or `null`.
    string getProperty(string key)
    {
        import flint.boot.context.properties.bind : PropertySourcesPlaceholdersResolver;

        if (!ConfigurationPropertyName.isValid(key))
            return null;
        auto property = ConfigurationPropertySources.find(data.getSources(), ConfigurationPropertyName.of(key));
        if (property is null)
            return null;
        return new PropertySourcesPlaceholdersResolver(data.getSources()).resolvePlaceholders(property.getValue());
    }

    /// The value of `key`, or `defaultValue`.
    string getProperty(string key, string defaultValue)
    {
        auto value = getProperty(key);
        return value is null ? defaultValue : value;
    }

    /// Whether `key` has a value.
    bool containsProperty(string key)
    {
        return getProperty(key) !is null;
    }

    /// `text` with `${...}` placeholders resolved.
    string resolvePlaceholders(string text)
    {
        import flint.boot.context.properties.bind : PropertySourcesPlaceholdersResolver;

        return new PropertySourcesPlaceholdersResolver(data.getSources()).resolvePlaceholders(text);
    }

    /// The active profiles.
    const(string)[] getActiveProfiles()
    {
        return data.getProfiles().getActive();
    }

    /// The default profiles.
    const(string)[] getDefaultProfiles()
    {
        return data.getProfiles().getDefault();
    }

    /// Whether any of the profile expressions matches the accepted profiles.
    bool acceptsProfiles(string[] profiles...)
    {
        import flint.boot.internal.core_env : matchesProfiles;

        auto accepted = data.getProfiles();
        return matchesProfiles(profiles, (string p) => accepted.isAccepted(p));
    }

    /// The property sources, highest precedence first, as Boot's `ConfigurationPropertySources.get` returns them.
    ConfigurationPropertySource[] getPropertySources() pure nothrow @nogc
    {
        return data.getSources();
    }
}

/// Prints a banner at startup.
interface Banner
{
    /// Where the banner goes.
    enum Mode
    {
        /// No banner.
        OFF,
        /// To standard output.
        CONSOLE,
        /// To the log, at INFO.
        LOG
    }

    /// Print the banner for `sourceClass` (its simple name, may be `null`) to `output`.
    void printBanner(ApplicationEnvironment environment, string sourceClass, scope void delegate(string) @safe output);
}

/// Flint Boot's default banner.
final class FlintBootBanner : Banner
{
    private enum art = `
  _____ _ _       _
 |  ___| (_)_ __ | |_
 | |_  | | | '_ \| __|
 |  _| | | | | | | |_
 |_|   |_|_|_| |_|\__|
`;
    private enum flintBoot = " :: Flint Boot :: ";
    private enum strapLineSize = 42;

    /// Print the art and the Flint Boot strap line.
    void printBanner(ApplicationEnvironment environment, string, scope void delegate(string) @safe output)
    {
        const version_ = " (v" ~ FlintBootVersion.getVersion() ~ ")";
        const used = version_.length + flintBoot.length;
        string padding;
        foreach (_; used .. strapLineSize)
            padding ~= ' ';
        const ansi = ansiEnabled(environment);
        output("\n" ~ art[1 .. $] ~ "\n" ~ ansiText(ansi, "32", flintBoot) ~ padding ~ ansiText(ansi,
                "2", version_) ~ "\n\n");
    }
}

/// A banner read from a text resource (`flint.banner.location`, default `classpath:banner.txt`), with Boot's
/// placeholders resolved in two passes as Boot does:
/// - first against the environment, the title, the ANSI codes and the versions, where an unknown version or title
///   leaves the placeholder for its `:default`;
/// - then with unknown versions and title as empty text.
///
/// The placeholders are `${application.version}` (from `flint.application.version`),
/// `${application.formatted-version}`, `${application.title}`, `${flint-boot.version}` (alias
/// `${spring-boot.version}`), `${flint-boot.formatted-version}`, and `${AnsiColor.*}`, `${AnsiBackground.*}`,
/// `${AnsiStyle.*}` and `${Ansi.*}` (including 8-bit colours such as `${AnsiColor.208}`).
class ResourceBanner : Banner
{
    private string text;

    /// A banner of `text`.
    this(string text) pure nothrow @nogc
    {
        this.text = text;
    }

    /// Print the resolved banner text.
    void printBanner(ApplicationEnvironment environment, string sourceClass, scope void delegate(string) @safe output)
    {
        output(render(environment, sourceClass) ~ "\n");
    }

    /// The banner with its placeholders resolved.
    string render(ApplicationEnvironment environment, string sourceClass = null)
    {
        import flint.boot.context.properties.bind : PropertySourcesPlaceholdersResolver;

        const ansi = ansiEnabled(environment);
        auto first = environment.getPropertySources() ~ [
            cast(ConfigurationPropertySource) titleSource(sourceClass, null),
            new AnsiPropertySource(ansi), versionSource(environment, null)
        ];
        auto banner = new PropertySourcesPlaceholdersResolver(first).resolvePlaceholders(text);
        ConfigurationPropertySource[] second = [
            titleSource(sourceClass, ""), versionSource(environment, "")
        ];
        return new PropertySourcesPlaceholdersResolver(second).resolvePlaceholders(banner);
    }

    /// Flint Boot's version; tests override it.
    protected string getBootVersion()
    {
        return FlintBootVersion.getVersion();
    }

    /// The application's title (Java reads the jar manifest's `Implementation-Title`); `null` when unknown.
    protected string getApplicationTitle(string)
    {
        return null;
    }

    private MapConfigurationPropertySource titleSource(string sourceClass, string fallback)
    {
        auto title = getApplicationTitle(sourceClass);
        auto source = new MapConfigurationPropertySource("title");
        if (title !is null || fallback !is null)
            source.put("application.title", title !is null ? title : fallback);
        return source;
    }

    private MapConfigurationPropertySource versionSource(ApplicationEnvironment environment, string fallback)
    {
        const application = environment.getProperty("flint.application.version");
        const boot = getBootVersion();
        auto source = new MapConfigurationPropertySource("version");
        void put(string key, string version_, bool formatted)
        {
            if (version_ !is null)
                source.put(key, formatted ? " (v" ~ version_ ~ ")" : version_);
            else if (fallback !is null)
                source.put(key, fallback);
        }

        put("application.version", application, false);
        put("application.formatted-version", application, true);
        foreach (prefix; ["flint-boot", "spring-boot"])
        {
            put(prefix ~ ".version", boot, false);
            put(prefix ~ ".formatted-version", boot, true);
        }
        return source;
    }
}

/// Boot's `AnsiPropertySource`: `${AnsiColor.RED}`, `${AnsiBackground.BLUE}`, `${AnsiStyle.BOLD}`, `${Ansi.*}`
/// and 8-bit `${AnsiColor.208}`, as escape codes when ANSI output is enabled and as empty text otherwise.
final class AnsiPropertySource : ConfigurationPropertySource
{
    import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyState;

    private bool encode;

    /// A source that encodes when `encode` is set.
    this(bool encode) pure nothrow @nogc
    {
        this.encode = encode;
    }

    ConfigurationProperty getConfigurationProperty(ConfigurationPropertyName name)
    {
        import std.uni : toUpper;

        if (name.getNumberOfElements() != 2)
            return null;
        const group = name.getElement(0, ConfigurationPropertyName.Form.UNIFORM);
        const key = name.getElement(1, ConfigurationPropertyName.Form.ORIGINAL).toUpper;
        const code = ansiCode(groupName(group) ~ "." ~ key);
        if (code is null)
            return null;
        return new ConfigurationProperty(this, name, encode ? "\x1b[" ~ code ~ "m" : "", "ansi");
    }

    /// ANSI names cannot be listed, so descendants are unknown.
    ConfigurationPropertyState containsDescendantOf(ConfigurationPropertyName)
    {
        return ConfigurationPropertyState.UNKNOWN;
    }

    /// ANSI names cannot be listed.
    ConfigurationPropertyName[] iterator()
    {
        return null;
    }

    string getUnderlyingSourceName()
    {
        return "ansi";
    }

    private static string groupName(string uniform) pure
    {
        switch (uniform)
        {
        case "ansicolor":
            return "AnsiColor";
        case "ansibackground":
            return "AnsiBackground";
        case "ansistyle":
            return "AnsiStyle";
        case "ansi":
            return "Ansi";
        default:
            return "";
        }
    }
}

/// Creates the application context `FlintApplication.run` refreshes.
interface ApplicationContextFactory
{
    /// A new context for `webApplicationType`.
    ConfigurableApplicationContext create(WebApplicationType webApplicationType);
}

/// Bootstraps and runs a Flint application.
class FlintApplication
{
    private ClassRef[] primarySources;
    private string mainApplicationClass;
    private Banner.Mode bannerMode = Banner.Mode.CONSOLE;
    private bool bannerModeSet;
    private Banner banner;
    private bool logStartupInfo = true;
    private string[] additionalProfiles;
    private string[string] defaultProperties;
    private WebApplicationType webApplicationType = WebApplicationType.NONE;
    private bool webApplicationTypeSet;
    private ApplicationContextFactory applicationContextFactory;
    private FailureAnalyzer[] failureAnalyzers;
    private ConfigDataResourceReader resourceReader;
    private string[string] environmentVariables;
    private bool environmentVariablesSet;
    private void delegate(string) @safe output;
    private LogSettings logSettings;

    /// An application whose configuration starts at `primarySources`.
    this(ClassRef[] primarySources...)
    {
        this.primarySources = primarySources.dup;
        if (primarySources.length)
            this.mainApplicationClass = simpleName(primarySources[0].name);
        this.logSettings = new LogSettings;
    }

    /// Run `App`, as `SpringApplication.run(App.class, args)`.
    static ConfigurableApplicationContext run(App)(string[] args)
    {
        import flint.engine.aot.name : typeNameOf;

        return new FlintApplication(ClassRef(typeNameOf!App)).run(args);
    }

    /// Run the application: configuration, banner, context, runners. Returns the running context. On failure
    /// the failure is reported, the context closed and the exception rethrown.
    ConfigurableApplicationContext run(string[] args)
    {
        const startNanos = monotonicNanos();
        auto applicationArguments = new DefaultApplicationArguments(args);
        ConfigurableApplicationContext context;
        try
        {
            auto environment = prepareEnvironment(applicationArguments);
            configureLogging(environment);
            auto printedBanner = printBanner(environment);
            if (logStartupInfo)
                logStarting(environment);
            context = createApplicationContext();
            context.setEnvironment(environment);
            context.registerSingleton("flintApplicationArguments", cast(Object) applicationArguments);
            if (printedBanner !is null)
                context.registerSingleton("flintBootBanner", cast(Object) printedBanner);
            context.refresh();
            if (logStartupInfo)
                logStarted(startNanos);
            callRunners(context, applicationArguments);
            return context;
        }
        catch (Exception failure)
        {
            handleRunFailure(context, failure);
            throw failure;
        }
    }

    /// Run `App` from `main`: Java's process stays alive while non-daemon server threads run, so this waits for
    /// the context to close. Returns the process exit code: 0, or 1 after a startup failure.
    static int main(App)(string[] args)
    {
        try
        {
            auto context = run!App(args.length ? args[1 .. $] : null);
            context.awaitTermination();
            return 0;
        }
        catch (Exception)
            return 1;
    }

    /// The exit code of `context`: the highest-magnitude code of its `ExitCodeGenerator` beans and of
    /// `generators`; the context is closed.
    static int exit(ConfigurableApplicationContext context, ExitCodeGenerator[] generators...)
    {
        import flint.engine.aot.name : typeNameOf;

        int code;
        void consider(int candidate)
        {
            if ((candidate > 0 && candidate > code) || (candidate < 0 && candidate < code))
                code = candidate;
        }

        foreach (generator; generators)
            consider(generator.getExitCode());
        if (context !is null && context.isActive())
        {
            foreach (bean; context.getBeanFactory().getBeansOfType(typeNameOf!ExitCodeGenerator))
            {
                if (auto generator = cast(ExitCodeGenerator) bean)
                    consider(generator.getExitCode());
            }
            context.close();
        }
        return code;
    }

    /// The class whose name the startup log uses.
    void setMainApplicationClass(ClassRef mainApplicationClass)
    {
        this.mainApplicationClass = simpleName(mainApplicationClass.name);
    }

    /// Where the banner goes (`flint.main.banner-mode`).
    void setBannerMode(Banner.Mode bannerMode)
    {
        this.bannerMode = bannerMode;
        this.bannerModeSet = true;
    }

    /// The banner to print instead of the resource or default one.
    void setBanner(Banner banner)
    {
        this.banner = banner;
    }

    /// Whether to log the "Starting" and "Started" lines (`flint.main.log-startup-info`).
    void setLogStartupInfo(bool logStartupInfo)
    {
        this.logStartupInfo = logStartupInfo;
    }

    /// Profiles active in addition to `flint.profiles.active`.
    void setAdditionalProfiles(string[] profiles...)
    {
        this.additionalProfiles = profiles.dup;
    }

    /// The additional profiles.
    const(string)[] getAdditionalProfiles() const pure nothrow @nogc
    {
        return additionalProfiles;
    }

    /// Properties with the lowest precedence.
    void setDefaultProperties(string[string] defaultProperties)
    {
        this.defaultProperties = defaultProperties.dup;
    }

    /// The kind of context to create (`flint.main.web-application-type`).
    void setWebApplicationType(WebApplicationType webApplicationType)
    {
        this.webApplicationType = webApplicationType;
        this.webApplicationTypeSet = true;
    }

    /// The web application type.
    WebApplicationType getWebApplicationType() const pure nothrow @nogc
    {
        return webApplicationType;
    }

    /// The factory of the application context.
    void setApplicationContextFactory(ApplicationContextFactory applicationContextFactory)
    {
        this.applicationContextFactory = applicationContextFactory;
    }

    /// Failure analyzers contributed by modules (Boot finds them in `spring.factories`).
    void addFailureAnalyzers(FailureAnalyzer[] analyzers...)
    {
        this.failureAnalyzers ~= analyzers;
    }

    /// Flint: read config files through `reader` (tests use an in-memory one).
    void setResourceReader(ConfigDataResourceReader reader)
    {
        this.resourceReader = reader;
    }

    /// Flint: use `variables` instead of the process environment (tests).
    void setEnvironmentVariables(string[string] variables)
    {
        this.environmentVariables = variables.dup;
        this.environmentVariablesSet = true;
    }

    /// Flint: send the banner and log lines to `output` instead of standard output (tests).
    void setOutput(void delegate(string) @safe output)
    {
        this.output = output;
        this.logSettings.sink = output;
    }

private:
    ApplicationEnvironment prepareEnvironment(DefaultApplicationArguments arguments)
    {
        import std.process : environment;

        ConfigDataEnvironmentOptions options;
        options.args = arguments.args;
        options.environment = environmentVariablesSet ? environmentVariables : environment.toAA();
        options.additionalProfiles = additionalProfiles;
        options.defaultProperties = defaultProperties;
        options.reader = resourceReader;
        auto result = new ApplicationEnvironment(new ConfigDataEnvironment(options).processAndApply());
        bindMainProperties(result);
        return result;
    }

    // `flint.main.*` binds onto the application, as Boot's `bindToSpringApplication` does.
    void bindMainProperties(ApplicationEnvironment environment)
    {
        import std.uni : toUpper;

        if (!bannerModeSet)
        {
            const mode = environment.getProperty("flint.main.banner-mode");
            if (mode !is null)
                bannerMode = parseEnum!(Banner.Mode)(mode, "flint.main.banner-mode");
        }
        const logInfo = environment.getProperty("flint.main.log-startup-info");
        if (logInfo !is null)
            logStartupInfo = logInfo.toUpper == "TRUE";
        if (!webApplicationTypeSet)
        {
            const type = environment.getProperty("flint.main.web-application-type");
            if (type !is null)
                webApplicationType = parseEnum!WebApplicationType(type, "flint.main.web-application-type");
        }
    }

    void configureLogging(ApplicationEnvironment environment)
    {
        import flint.boot.context.properties.source : ConfigurationPropertyName;
        import std.uni : toUpper;

        logSettings.format.applicationName = environment.getProperty("flint.application.name", "");
        logSettings.format.applicationGroup = environment.getProperty("flint.application.group", "");
        logSettings.format.ansi = ansiEnabled(environment);
        auto prefix = ConfigurationPropertyName.of("logging.level");
        foreach (name; ConfigurationPropertySources.names(environment.getPropertySources()))
        {
            if (!prefix.isAncestorOf(name))
                continue;
            const logger = name.subName(2).toString();
            const level = environment.getProperty(name.toString());
            if (level !is null)
                logSettings.levels[logger] = parseEnum!LogLevel(level.toUpper, name.toString());
        }
    }

    Banner printBanner(ApplicationEnvironment environment)
    {
        if (bannerMode == Banner.Mode.OFF)
            return null;
        auto chosen = banner !is null ? banner : resourceBanner(environment);
        if (chosen is null)
            chosen = new FlintBootBanner;
        string text;
        chosen.printBanner(environment, mainApplicationClass, (string part) { text ~= part; });
        if (bannerMode == Banner.Mode.LOG)
            log().info(text);
        else
            write(text);
        return chosen;
    }

    Banner resourceBanner(ApplicationEnvironment environment)
    {
        import flint.boot.context.config : FileConfigDataResourceReader;
        import std.algorithm.searching : startsWith;
        import std.path : buildNormalizedPath;

        const location = environment.getProperty("flint.banner.location", "classpath:banner.txt");
        string path = location;
        if (path.startsWith("classpath:"))
            path = buildNormalizedPath("resources", path["classpath:".length .. $].stripSlash);
        else if (path.startsWith("file:"))
            path = path["file:".length .. $];
        ConfigDataResourceReader reader = resourceReader is null ? new FileConfigDataResourceReader : resourceReader;
        auto bytes = reader.read(path);
        if (bytes is null)
            return null;
        return new ResourceBanner((cast(const(char)[]) bytes).idup);
    }

    void logStarting(ApplicationEnvironment environment)
    {
        import flint.boot.internal.log : processId;
        import std.conv : to;
        import std.file : getcwd, thisExePath;

        string message = "Starting " ~ applicationName();
        const version_ = environment.getProperty("flint.application.version");
        if (version_.length)
            message ~= " v" ~ version_;
        message ~= " using Flint " ~ FlintBootVersion.getVersion() ~ " with PID " ~ processId().to!string;
        message ~= " (" ~ thisExePath() ~ " started by " ~ userName() ~ " in " ~ getcwd() ~ ")";
        log().info(message);
        log().info(profileMessage(environment));
    }

    static string profileMessage(ApplicationEnvironment environment)
    {
        import std.algorithm.iteration : map;
        import std.array : join;
        import std.conv : to;

        const active = environment.getActiveProfiles();
        string quoted(const(string)[] profiles)
        {
            return profiles.map!(p => "\"" ~ p ~ "\"").join(", ");
        }

        if (active.length == 0)
        {
            const defaults = environment.getDefaultProfiles();
            return "No active profile set, falling back to " ~ defaults.length.to!string ~ " default profile" ~ (
                    defaults.length == 1 ? "" : "s") ~ ": " ~ quoted(defaults);
        }
        return "The following " ~ active.length.to!string ~ " profile" ~ (active.length == 1
                ? " is" : "s are") ~ " active: " ~ quoted(active);
    }

    void logStarted(long startNanos)
    {
        const taken = (monotonicNanos() - startNanos) / 1_000_000;
        log().info("Started " ~ applicationName() ~ " in " ~ seconds(
                taken) ~ " seconds (process running for " ~ seconds(processUptimeMillis()) ~ ")");
    }

    ConfigurableApplicationContext createApplicationContext()
    {
        if (applicationContextFactory is null)
            throw new IllegalStateException("No ApplicationContextFactory: add a context module (flint:context, or "
                    ~ "flint:boot-starter-web for a servlet context) to the application");
        return applicationContextFactory.create(webApplicationType);
    }

    void callRunners(ConfigurableApplicationContext context, DefaultApplicationArguments arguments)
    {
        import flint.engine.aot.name : typeNameOf;

        foreach (bean; context.getBeanFactory().getBeansOfType(typeNameOf!Runner))
        {
            if (auto applicationRunner = cast(ApplicationRunner) bean)
                applicationRunner.run(arguments);
            else if (auto commandLineRunner = cast(CommandLineRunner) bean)
                commandLineRunner.run(arguments.args.dup);
        }
    }

    void handleRunFailure(ConfigurableApplicationContext context, Exception failure)
    {
        import flint.boot.diagnostics.analyzer : bootFailureAnalyzers;

        FailureAnalysisReporter[] reporters = [new LoggingFailureAnalysisReporter(log())];
        auto analyzers = new FailureAnalyzers(failureAnalyzers ~ bootFailureAnalyzers(), reporters);
        if (!analyzers.reportException(failure))
            log().error("Application run failed", failure);
        if (context !is null)
        {
            try
                context.close();
            catch (Exception)
            {
                // Boot logs a failing close at WARN and keeps the original failure.
            }
        }
    }

    Log log()
    {
        return new Log(primarySources.length ? primarySources[0].name : "flint.boot.FlintApplication", logSettings);
    }

    string applicationName() const pure nothrow @nogc
    {
        return mainApplicationClass.length ? mainApplicationClass : "application";
    }

    void write(string text)
    {
        import flint.term : Stream, writeStream;

        if (output !is null)
            output(text);
        else
            cast(void) writeStream(Stream.output, text);
    }
}

/// Generates the process entry point beside the application class (deviation D-1): `main` runs `App`, waits for
/// its context to close, and returns the exit code. When `App` declares its own `static int main(string[])` (to
/// customise `FlintApplication` as a Java `main` would), that is called instead.
mixin template FlintMain(App)
{
    int main(string[] args)
    {
        static if (__traits(compiles, App.main(args)))
            return App.main(args);
        else
            return FlintApplication.main!App(args);
    }
}

private:

E parseEnum(E)(string text, string property)
{
    import std.array : replace;
    import std.uni : toUpper;

    const normalized = text.toUpper.replace("-", "_");
    foreach (index, name; enumNames!E)
    {
        if (normalized == name)
            return cast(E) index;
    }
    throw new IllegalArgumentException("Invalid value '" ~ text ~ "' for " ~ property);
}

template enumNames(E)
{
    static if (is(E == Banner.Mode))
        static immutable enumNames = ["OFF", "CONSOLE", "LOG"];
    else static if (is(E == WebApplicationType))
        static immutable enumNames = ["NONE", "SERVLET", "REACTIVE"];
    else static if (is(E == LogLevel))
        static immutable enumNames = ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "OFF"];
}

string simpleName(string qualified) pure nothrow @nogc
{
    import flint.engine.aot.name : simpleTypeName;

    return simpleTypeName(qualified);
}

string stripSlash(string path) pure nothrow @nogc
{
    while (path.length && path[0] == '/')
        path = path[1 .. $];
    return path;
}

string seconds(long millis) pure
{
    import std.format : format;

    // Java's `double` printing of `millis / 1000.0`: at least one fractional digit, no trailing zeros.
    auto text = format("%.3f", millis / 1000.0);
    while (text.length > 3 && text[$ - 1] == '0' && text[$ - 2] != '.')
        text = text[0 .. $ - 1];
    return text;
}

long monotonicNanos()
{
    import core.time : MonoTime;

    return (MonoTime.currTime - MonoTime.zero).total!"nsecs";
}

long processUptimeMillis()
{
    import std.file : readText;
    import std.string : split;
    import std.conv : to;

    try
    {
        // Linux: field 22 of /proc/self/stat is the start time in clock ticks since boot.
        const stat = readText("/proc/self/stat");
        const fields = stat[lastIndexOf(stat, ')') + 2 .. $].split(' ');
        const startTicks = fields[19].to!long;
        const uptime = readText("/proc/uptime").split(' ')[0].to!double;
        return cast(long)((uptime - startTicks / 100.0) * 1000);
    }
    catch (Exception)
        return 0;
}

size_t lastIndexOf(string text, char ch) pure nothrow @nogc
{
    foreach_reverse (i, c; text)
    {
        if (c == ch)
            return i;
    }
    return 0;
}

string userName()
{
    import std.process : environment;

    return environment.get("USER", environment.get("USERNAME", "unknown"));
}

bool ansiEnabled(ApplicationEnvironment environment)
{
    import std.uni : toUpper;

    const mode = environment.getProperty("flint.output.ansi.enabled", "DETECT").toUpper;
    if (mode == "ALWAYS")
        return true;
    if (mode == "NEVER")
        return false;
    import flint.term : Stream, describe;
    import std.process : env = environment;

    return describe(Stream.output).terminal && env.get("TERM", "") != "dumb";
}

string ansiText(bool ansi, string code, string text) pure
{
    return ansi ? "\x1b[" ~ code ~ "m" ~ text ~ "\x1b[0;39m" : text;
}

// Boot's AnsiColor, AnsiBackground and AnsiStyle names, prefixed as AnsiPropertySource exposes them.
string ansiCode(string name) pure
{
    import std.algorithm.searching : startsWith;

    static immutable string[] colors = [
        "DEFAULT", "BLACK", "RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "WHITE",
        "BRIGHT_BLACK", "BRIGHT_RED", "BRIGHT_GREEN", "BRIGHT_YELLOW", "BRIGHT_BLUE",
        "BRIGHT_MAGENTA", "BRIGHT_CYAN", "BRIGHT_WHITE"
    ];
    static immutable string[] foreground = [
        "39", "30", "31", "32", "33", "34", "35", "36", "37", "90", "91", "92", "93", "94", "95", "96",
        "97"
    ];
    static immutable string[] background = [
        "49", "40", "41", "42", "43", "44", "45", "46", "47", "100", "101", "102", "103", "104", "105",
        "106", "107"
    ];
    static immutable string[] styles = ["NORMAL", "BOLD", "FAINT", "ITALIC", "UNDERLINE"];
    static immutable string[] styleCodes = ["0", "1", "2", "3", "4"];
    string lookup(string key, const string[] names, const string[] codes)
    {
        foreach (index, candidate; names)
        {
            if (candidate == key)
                return codes[index];
        }
        return null;
    }

    if (name.startsWith("AnsiColor."))
        return eightBit(name["AnsiColor.".length .. $], "38;5;",
                lookup(name["AnsiColor.".length .. $], colors, foreground));
    if (name.startsWith("AnsiBackground."))
        return eightBit(name["AnsiBackground.".length .. $], "48;5;",
                lookup(name["AnsiBackground.".length .. $], colors, background));
    if (name.startsWith("AnsiStyle."))
        return lookup(name["AnsiStyle.".length .. $], styles, styleCodes);
    if (name.startsWith("Ansi."))
    {
        const key = name["Ansi.".length .. $];
        if (auto code = lookup(key, colors, foreground))
            return code;
        if (key.startsWith("BG_"))
            return lookup(key[3 .. $], colors, background);
        return lookup(key, styles, styleCodes);
    }
    return null;
}

// Boot's Ansi8BitColor: a number from 0 to 255 is an 8-bit colour.
string eightBit(string key, string prefix, string named) pure
{
    import std.conv : ConvException, to;

    if (named !is null)
        return named;
    try
    {
        const code = key.to!int;
        return code >= 0 && code <= 255 ? prefix ~ key : null;
    }
    catch (ConvException)
        return null;
}
