/// flint:boot-autoconfigure-web: Flint Boot's auto-configuration for flint:web (ADR-029 section 8, ADR-028
/// section 8).
///
/// `WebServerAutoConfiguration` binds `[server]`, registers the single-page front end when `[spa]` is configured,
/// and launches the server: every `@RestController` bean is served, and every `ServerCustomizer` bean (the
/// actuator's endpoints, for one) registers on it. Started with `--openapi`, the application prints the
/// controllers' OpenAPI document instead.
module flint.boot_autoconfigure_web;

import flint.arena : Error, Status;
import flint.config : ConfigurationProperties;
import flint.di : AutoConfiguration, Bind, Launcher, Provided;

public import flint.boot_autoconfigure_web.spa : SpaController, SpaProperties;

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

/// The web server's auto-configuration: `[server]`, the front end when `[spa]` is configured, and the server.
alias WebServerAutoConfiguration = AutoConfiguration!(Provided!ServerProperties,
        Provided!SpaProperties, SpaController, Launcher!WebServer);

/// Serves the application's controllers on `[server]` until the server stops.
struct WebServer
{
    /// `--openapi` prints the controllers' OpenAPI document; `flint openapi` calls it.
    static bool command(Context)(string[] args, out int code)
    {
        foreach (argument; args.length > 1 ? args[1 .. $] : null)
        {
            if (argument == "--openapi")
            {
                import flint.term : Stream, writeStream;
                import flint.web : openApiDocument;

                enum document = openApiDocument!(ApiControllers!(Context.Registered))("Flint application", "0.0.0");
                code = writeStream(Stream.output, document ~ "\n").code == Status.ok ? 0 : 1;
                return true;
            }
        }
        return false;
    }

    /// Serve every `@RestController` bean, after every `ServerCustomizer` bean registers.
    static int launch(Context)(ref Context context, string[] args)
    {
        import flint.boot : report;
        import flint.web : Server, ServerOptions, serve;

        alias Registered = Context.Registered;
        Controllers!Registered application;
        static foreach (index, Controller; Controllers!Registered.Types)
            application.items[index] = context.get!Controller();
        const settings = context.get!ServerProperties();
        ServerOptions server;
        server.address = settings.address;
        server.port = settings.port;
        server.cores = settings.cores;
        server.maxBodyBytes = settings.maxBodyBytes;
        scope Error delegate(ref Server) @safe customize = (ref Server started) @safe {
            static foreach (Customizer; Customizers!Registered)
            {
                {
                    Error customized = context.get!Customizer().customize(started);
                    if (customized.code != Status.ok)
                        return customized;
                }
            }
            return Error.init;
        };
        const served = serve(application, server, customize);
        if (served.code == Status.ok || served.code == Status.cancelled)
            return 0;
        return report(1, "server: " ~ served.message);
    }
}

/// The keys among the registrations that are `ServerCustomizer`s, in order.
template Customizers(Registered...)
{
    import std.meta : AliasSeq;
    import flint.web : ServerCustomizer;

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
            static if (is(Key == class) && is(Key : ServerCustomizer))
                alias collect = AliasSeq!(Key, collect!(index + 1));
            else
                alias collect = collect!(index + 1);
        }
    }

    alias Customizers = collect!0;
}

/// The application's own controllers, without the front end's `SpaController`, for the OpenAPI document.
struct ApiControllers(Registered...)
{
    import std.meta : Filter;

    private enum bool api(T) = !is(T == SpaController);
    /// The controller types.
    alias Types = Filter!(api, Controllers!Registered.Types);
    /// The controllers.
    Types items;
}

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
