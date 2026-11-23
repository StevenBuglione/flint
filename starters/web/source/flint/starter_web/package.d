/// flint:starter-web: a web application in one call (ADR-028 section 2).
///
/// The module re-exports what a web application writes (UDAs, `Result`, configuration and validation attributes),
/// so the application imports `flint.starter_web` alone.
///
/// `runApplication!(Beans...)(args)` binds every configuration type the beans register, starts the DI context,
/// serves every `@RestController` bean on the `[server]` address, and stops the context when the server stops:
///
/// ---
/// int main(string[] args)
/// {
///     return runApplication!(NoteRepository, NoteService, NoteController)(args);
/// }
/// ---
module flint.starter_web;

// What a web application writes, from one import: `import flint.starter_web : Get, RestController, Service, ...;`.
public import flint.arena : Error, Result, Status, Text;
public import flint.config : ConfigurationProperties, Default, Env, Required, Secret;
public import flint.di : AutoConfiguration, Bind, Component, ConditionalOnConfig,
    ConditionalOnMissingBean, Inject, Named, PostConstruct, PreDestroy, Provided, Repository, Service;
public import flint.validate : Email, Max, Min, NotBlank, Pattern, Size, Valid;
public import flint.web : ControllerAdvice, Delete, Get, PathVariable, Post, Put, QueryParam,
    Request, RequestBody, RequestContext, Response, RestController;

@safe:

/// The `[server]` section. Every key is optional.
@ConfigurationProperties("server")
struct ServerProperties
{
    /// Bind address.
    string address = "127.0.0.1";
    /// TCP port.
    ushort port = 8080;
    /// HTTP reactor workers.
    uint cores = 1;
    /// Largest request body in bytes.
    size_t maxBodyBytes = 1_048_576;
}

/// The starter's registrations: the server settings, bound from configuration by `runApplication`.
alias WebAutoConfiguration = AutoConfiguration!(Provided!ServerProperties);

/// Exit codes of `runApplication` before the server runs.
enum StartupExit : int
{
    /// Configuration did not bind; the message names the key.
    configuration = 3,
    /// A bean's constructor or `@PostConstruct` failed.
    context = 4
}

/// Run a web application: bind configuration from `config/` (with `--set key=value` and `--profile name`
/// arguments), start the DI context of `WebAutoConfiguration` and `Beans`, serve every `@RestController` bean, and
/// shut the context down after the server stops. Beans are starters' auto-configuration lists and the
/// application's own services, repositories and controllers.
int runApplication(Beans...)(string[] args)
{
    import flint.arena : Status;
    import flint.di : AppContext;
    import flint.web : ServerOptions, run = runApplication;

    AppContext!(WebAutoConfiguration, Beans) context;
    alias Registered = typeof(context).Registered;
    const configured = bindConfiguration(context, args.length > 1 ? args[1 .. $] : null);
    if (configured.code != Status.ok)
        return report(StartupExit.configuration, "configuration: " ~ configured.message);
    const started = context.initialize();
    if (started.code != Status.ok)
        return report(StartupExit.context, "startup: " ~ started.message);
    scope (exit)
        context.shutdown();

    alias Served = Controllers!Registered;
    Served application;
    static foreach (index, Controller; Served.Types)
        application.items[index] = context.get!Controller();
    const settings = context.get!ServerProperties();
    ServerOptions server;
    server.address = settings.address;
    server.port = settings.port;
    server.cores = settings.cores;
    server.maxBodyBytes = settings.maxBodyBytes;
    return run(application, server);
}

/// Bind every `Provided!T` registration whose `T` is a `@ConfigurationProperties` struct, from one snapshot of the
/// configuration, and provide it to the context. Keys that no registered type claims are errors.
imported!"flint.arena".Error bindConfiguration(Context)(ref Context context, string[] arguments)
{
    import flint.arena : Status;
    import flint.config : ConfigOptions, load;

    alias Types = ConfigurationTypes!(Context.Registered);
    static if (Types.length == 0)
        return imported!"flint.arena".Error.init;
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
        return imported!"flint.arena".Error.init;
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

/// The application struct flint:web serves: one field per `@RestController` registration, in order.
struct Controllers(Registered...)
{
    import std.meta : AliasSeq;

    private template collect(size_t index)
    {
        static if (index == Registered.length)
            alias collect = AliasSeq!();
        else static if (controller!(Registered[index]))
            alias collect = AliasSeq!(Registered[index], collect!(index + 1));
        else
            alias collect = collect!(index + 1);
    }

    /// The controller types.
    alias Types = collect!0;
    /// The controllers, served in order.
    Types items;
}

private enum bool controller(T) = () {
    import flint.web : RestController;

    static if (is(T == struct) || is(T == class))
    {
        static foreach (attribute; __traits(getAttributes, T))
        {
            static if (is(typeof(attribute) == RestController))
                return true;
        }
    }
    return false;
}();

private int report(int code, string message)
{
    import flint.term : Stream, writeStream;

    writeStream(Stream.error, message ~ "\n");
    return code;
}
