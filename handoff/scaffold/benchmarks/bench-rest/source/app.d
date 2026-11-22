module app;
import flint.arena : Error, Result, Status;
import flint.web : RestController, Get, RequestContext, Response, ServerOptions, runApplication;
import flint.serde : encodeJson;
import std.conv : to;
import std.string : lastIndexOf;

@safe:
/// Exact typed response shared with the Go comparison workload.
struct Message
{
    /// Greeting encoded on every measured request.
    string message = "hello";
    /// Numeric JSON field included in the fixed payload.
    int n = 42;
}

/// Minimal transport and serialization benchmark routes.
@RestController("")
struct Controller
{
    /// Serialize the fixed DTO into the current request arena.
    @Get("/json")
    Result!Response json(ref scope RequestContext context) nothrow @nogc
    {
        Message value;
        auto encoded = encodeJson(value, context.arena);
        if (!encoded.ok())
            return Result!Response(Response.init, encoded.error);
        return Result!Response(Response(200, "application/json", encoded.value), Error.init);
    }

    /// Liveness endpoint used before the load phase.
    @Get("/health")
    Result!Response health(ref scope RequestContext context) nothrow @nogc
    {
        auto copied = context.arena.copyIn(cast(const(ubyte)[]) "ok\n");
        if (!copied.ok())
            return Result!Response(Response.init, copied.error);
        return Result!Response(Response(200, "text/plain; charset=utf-8", copied.value), Error.init);
    }
}

/// Explicit benchmark route registry.
struct Application
{
    /// Single controller with no external application dependencies.
    Controller controller;
}

int main(string[] args)
{
    ServerOptions options;
    options.port = 8080;
    options.cores = 2;
    options.http2 = false;
    options.maxHeaderBytes = 8192;
    if (args.length != 1)
    {
        if (args.length != 3 || args[1] != "--listen")
            return 2;
        auto split = args[2].lastIndexOf(':');
        if (split < 1)
            return 2;
        options.address = args[2][0 .. cast(size_t) split];
        try
        {
            options.port = to!ushort(args[2][cast(size_t) split + 1 .. $]);
        }
        catch (Exception)
        {
            return 2;
        }
    }
    Application application;
    return runApplication(application, options);
}
