/// Frozen router-only requests using the same dispatch as the HTTP transport.
module flint.web.micro_router;

import flint.arena : Error, RequestArena, Result, Status;
import flint.web : Method, Request, RequestContext, Response;
import flint.web.dispatch : executeRoute;
import flint.web.router : RouteTable;
import flint.web.types : RequestMetadata;
import flint_micro.timing : BatchResult;

@safe:

/// Route table committed for every observation.
immutable string[3] routes = ["/health", "/users/:id", "/assets/*tail"];
/// Request corpus committed for every observation, ordered by literal, parameter, wildcard, and miss.
immutable string[4] paths = ["/health", "/users/42", "/assets/img/logo.svg", "/missing"];

private enum healthStatus = 200;
private enum userStatus = 201;
private enum assetStatus = 202;
private immutable ushort[4] expected = [healthStatus, userStatus, assetStatus, 404];

/// Prepared copies of the request paths and their route handlers.
final class RouterCase
{
    private RouteTable table;
    private ubyte[1024] backing;
    private RequestContext* context;
    private RequestMetadata[paths.length] requests;

    /// Register routes and prepare checked arena handles outside measurement.
    bool open()
    {
        table = new RouteTable;
        context = new RequestContext(RequestArena(backing[]));
        if (table.insert(Method.get, routes[0], &health).code != Status.ok
                || table.insert(Method.get, routes[1], &user).code != Status.ok
                || table.insert(Method.get, routes[2], &asset).code != Status.ok)
            return false;
        foreach (index, ref request; requests)
        {
            const path = context.arena.copyIn(cast(const(ubyte)[]) paths[index]);
            if (!path.ok())
                return false;
            request.valid = true;
            request.generation = 1;
            request.method = Method.get;
            request.path = path.value;
        }
        return true;
    }

    /// Check selected handlers and captured spans for every named case.
    BatchResult run(uint count) nothrow @nogc
    {
        ulong checksum;
        foreach (index; 0 .. count)
        {
            const entry = index % paths.length;
            const executed = executeRoute(table, &requests[entry], *context);
            if (!executed.ok() && executed.error.code != Status.notFound)
                return BatchResult.init;
            const result = executed.ok() ? executed.value.status : 404;
            if (result != expected[entry])
                return BatchResult.init;
            checksum += result;
        }
        return BatchResult(count, checksum);
    }

    private Result!Response health(ref scope Request request, ref scope RequestContext ctx) nothrow @nogc
    {
        if (request.capture("id").ok() || request.capture("tail").ok())
            return mismatch();
        return Result!Response(Response(healthStatus));
    }

    private Result!Response user(ref scope Request request, ref scope RequestContext ctx) nothrow @nogc
    {
        return captured(request, ctx, "id", "42") ? Result!Response(Response(userStatus)) : mismatch();
    }

    private Result!Response asset(ref scope Request request, ref scope RequestContext ctx) nothrow @nogc
    {
        return captured(request, ctx, "tail", "img/logo.svg") ? Result!Response(Response(assetStatus)) : mismatch();
    }
}

private bool captured(ref scope Request req, ref scope RequestContext ctx, string field, string value) nothrow @nogc
{
    const range = req.capture(field);
    const path = req.path();
    if (!range.ok() || !path.ok())
        return false;
    const start = range.value.start;
    const end = range.value.end;
    bool equal;
    const status = ctx.arena.read(path.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        equal = start <= end && end <= bytes.length && bytes[start .. end] == cast(const(ubyte)[]) value;
    });
    return status == Status.ok && equal;
}

private Result!Response mismatch() nothrow @nogc
{
    return Result!Response(Response.init, Error(Status.ioError, "router microbenchmark captured an unexpected path"));
}
