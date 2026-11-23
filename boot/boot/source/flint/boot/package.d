/// flint:boot: the application runner (ADR-029 section 8, ADR-028 section 8).
///
/// `runApplication!(Beans...)(args)` is Spring Boot's `SpringApplication.run` for an explicit bean list:
/// - each launcher (an auto-configuration's `Launcher!T`, such as the web server's) may answer a command first,
///   like `--openapi`;
/// - configuration binds from `config/` into every `Provided!T` whose `T` is a `@ConfigurationProperties` struct,
///   from one snapshot that includes `--set key=value` and `--profile name`, so a key no type claims is an error;
/// - the DI context starts;
/// - the first launcher runs the application (the web server serves), and without one the run ends;
/// - the context shuts down.
///
/// Start-up failures are reported on standard error with the key, bean or address that caused them.
module flint.boot;

import flint.arena : Error, Status;
import flint.config : ConfigurationProperties;
import flint.di : Bind, Provided;

public import flint.boot.application : AutoConfigurationList, CommandLineRunner, Exclude,
    FlintApplication, FlintMain, ScannedBeans;

@safe:

/// Exit codes of `runApplication` before the application runs.
enum StartupExit : int
{
    /// Configuration did not bind; the message names the key.
    configuration = 3,
    /// A bean's constructor or `@PostConstruct` failed.
    context = 4
}

/// Run the application of `Beans`: auto-configuration lists and the application's own beans.
int runApplication(Beans...)(string[] args)
{
    import flint.di : AppContext;

    AppContext!Beans context;
    alias Context = typeof(context);
    static foreach (Launcher; Context.Launchers)
    {
        static if (__traits(hasMember, Launcher, "command"))
        {
            {
                int code;
                if (Launcher.command!Context(args, code))
                    return code;
            }
        }
    }
    const configured = bindConfiguration(context, args.length > 1 ? args[1 .. $] : null);
    if (configured.code != Status.ok)
        return report(StartupExit.configuration, "configuration: " ~ configured.message);
    const started = context.initialize();
    if (started.code != Status.ok)
        return report(StartupExit.context, "startup: " ~ started.message);
    scope (exit)
        context.shutdown();
    static foreach (Runner; Runners!(Context.Registered))
    {
        {
            const ran = context.get!Runner().run(args);
            if (ran != 0)
                return ran;
        }
    }
    static if (Context.Launchers.length)
        return Context.Launchers[0].launch(context, args);
    else
        return 0;
}

/// Bind every `Provided!T` registration whose `T` is a `@ConfigurationProperties` struct, from one snapshot of the
/// configuration, and provide it to the context. Keys that no registered type claims are errors.
Error bindConfiguration(Context)(ref Context context, string[] arguments)
{
    import flint.config : ConfigOptions, load;

    alias Types = ConfigurationTypes!(Context.Registered);
    static if (Types.length == 0)
        return Error.init;
    else
    {
        ConfigOptions options;
        options.directory = "config";
        options.arguments = arguments;
        Types values;
        const loaded = load(options, values);
        if (loaded.code != Status.ok)
            return loaded;
        static foreach (index; 0 .. Types.length)
        {
            {
                const provided = context.provide(values[index]);
                if (provided.code != Status.ok)
                    return provided;
            }
        }
        return Error.init;
    }
}

/// The `@ConfigurationProperties` types among `Provided!T` registrations, in order.
template ConfigurationTypes(Registered...)
{
    import std.meta : AliasSeq;

    template collect(size_t index)
    {
        static if (index == Registered.length)
            alias collect = AliasSeq!();
        else static if (is(Registered[index] == Provided!T, T) && configurationType!T)
            alias collect = AliasSeq!(T, collect!(index + 1));
        else
            alias collect = collect!(index + 1);
    }

    alias ConfigurationTypes = collect!0;
}

private enum bool configurationType(T) = () {
    static foreach (attribute; __traits(getAttributes, T))
    {
        static if (is(typeof(attribute) == ConfigurationProperties))
            return true;
    }
    return false;
}();

/// The keys of the `CommandLineRunner` beans among the registrations, in order.
template Runners(Registered...)
{
    import std.meta : AliasSeq;

    template collect(size_t index)
    {
        static if (index == Registered.length)
            alias collect = AliasSeq!();
        else
        {
            static if (is(Registered[index] == Bind!(Contract, Implementation), Contract, Implementation))
                alias Key = Contract;
            else static if (is(Registered[index] == Provided!Value, Value))
                alias Key = Value;
            else
                alias Key = Registered[index];
            static if (is(Key == class) && is(Key : CommandLineRunner))
                alias collect = AliasSeq!(Key, collect!(index + 1));
            else
                alias collect = collect!(index + 1);
        }
    }

    alias Runners = collect!0;
}

/// Print the banner, `resources/banner.txt` or Flint's, the application and the active profile to standard error,
/// as Spring Boot does at start. `--banner=off` or `FLINT_MAIN_BANNER_MODE=off` turns it off, and `--openapi`
/// prints none.
void printBanner(string application, scope const string[] args)
{
    import std.file : exists, readText;
    import std.process : environment;
    import flint.term : Stream, writeStream;

    foreach (argument; args.length > 1 ? args[1 .. $] : null)
    {
        if (argument == "--banner=off" || argument == "--openapi")
            return;
    }
    if (environment.get("FLINT_MAIN_BANNER_MODE", "console") == "off")
        return;
    string banner = defaultBanner;
    try
    {
        if (exists("resources/banner.txt"))
            banner = readText("resources/banner.txt");
    }
    catch (Exception)
    {
    }
    writeStream(Stream.error, banner ~ (banner.length && banner[$ - 1] == '\n'
            ? "" : "\n") ~ "Starting " ~ application
            ~ " using Flint\nThe following profile is active: \"" ~ activeProfile(args) ~ "\"\n");
}

/// The configuration profile: `--profile name`, else `FLINT_PROFILE`, else `dev`.
string activeProfile(scope const string[] args)
{
    import std.algorithm.searching : startsWith;
    import std.process : environment;

    foreach (index, argument; args)
    {
        if (argument.startsWith("--profile="))
            return argument["--profile=".length .. $];
        if (argument == "--profile" && index + 1 < args.length)
            return args[index + 1];
    }
    return environment.get("FLINT_PROFILE", "dev");
}

private enum defaultBanner = `
  _____ _ _       _
 |  ___| (_)_ __ | |_
 | |_  | | | '_ \| __|
 |  _| | | | | | | |_
 |_|   |_|_|_| |_|\__|
`;

/// Write a start-up failure to standard error and return `code`.
int report(int code, string message)
{
    import flint.term : Stream, writeStream;

    writeStream(Stream.error, message ~ "\n");
    return code;
}
