/// Shared canonical minimal REST profile and typed response.
module flint_bench_rest.profile;

import flint.arena : Error, Result;
import flint.serde : encodeJson;
import flint.engine.web : Get, RequestContext, Response, RestController, ServerOptions;

@safe:

/// The byte-for-byte canonical JSON response.
enum jsonBody = "{\"message\":\"hello\",\"n\":42}";

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

/// Select the same startup limits and HTTP/1.1 transport for both probes.
ServerOptions minimalRestOptions() pure nothrow @nogc
{
    ServerOptions options;
    options.port = 8080;
    options.cores = 2;
    options.http2 = false;
    options.maxHeaderBytes = 8192;
    return options;
}
