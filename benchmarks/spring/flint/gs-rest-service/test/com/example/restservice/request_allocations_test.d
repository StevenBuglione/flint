/++
The per-request allocation gate for gs-rest-service (work-queue item 28, decisions 9a9aefa0;
policy/request-allocations.json).

The application runs in-process on the real servlet path (`FlintApplication.run`, one reactor thread, port 0), on
druntime's own collector with flint.arena's allocation counter in front of it. Every request of the side-by-side suite
(benchmarks/spring/suites/requests/gs-rest-service.json, exported from the Python suite) is replayed over one
keep-alive connection after warm-up, and the server threads' GC allocations and bytes for it are compared with its
budget. Failures name the top allocating functions.

Measuring without a hook in the server: requests on one connection are served in order, so between two readings of
the server threads' totals, taken after the client has a response, lie the request's own allocations plus parts of
its neighbours'. Each measured request sits between two fences (`GET /greeting`), so a window holds the request's full
cost plus one fence's, and two fences in a row hold exactly two fences' costs. A request's cost is then the window
less half the fence pair, exactly, when costs do not depend on time; the minimum of three windows takes out a rare
periodic allocation. Set FLINT_REQUEST_ALLOCATIONS=record to print the measured costs instead of failing.
+/
module com.example.restservice.request_allocations_test;

import com.example.restservice : RestServiceApplication;
import core.memory : GC;
import flint.arena.gc : Allocations, installAllocationCounter, otherThreadsAllocations,
    recordAllocationSites, thisThreadAllocations, topAllocationSites, uninstallAllocationCounter;
import flint.boot : FlintApplication;
import flint.boot.web.server.servlet.context : ServletWebServerApplicationContext;
import std.json : JSONType, JSONValue, parseJSON;
import std.socket : InternetAddress, Socket, TcpSocket;

@safe:

private enum app = "gs-rest-service";
private enum requestsPath = "../../suites/requests/" ~ app ~ ".json";
private enum budgetsPath = "../../../../policy/request-allocations.json";

/// One suite request, as raw HTTP/1.1.
private struct Exchange
{
    string name;
    string text;
    bool head;
}

private Exchange exchangeOf(JSONValue request)
{
    import std.conv : to;

    const method = request["method"].str;
    const 
    body = request["body"].type == JSONType.string ? request["body"].str : null;
    string text = method ~ " " ~ request["path"].str ~ " HTTP/1.1\r\nHost: localhost\r\n";
    foreach (header; request["headers"].arrayNoRef)
        text ~= header[0].str ~ ": " ~ header[1].str ~ "\r\n";
    if (body !is null)
        text ~= "Content-Length: " ~ body.length.to!string ~ "\r\n";
    return Exchange(request["name"].str, text ~ "\r\n" ~ body, method == "HEAD");
}

/// A keep-alive client that reads each response to its end, and reconnects after a `Connection: close` response.
private struct Client
{
    Socket socket;
    ushort port;
    char[] pending;

    this(ushort port)
    {
        this.port = port;
        socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
    }

    void exchange(ref const Exchange request)
    {
        import std.conv : to;
        import std.string : indexOf, toLower;

        for (const(char)[] rest = request.text; rest.length;)
        {
            const sent = socket.send(rest);
            assert(sent > 0, "send failed: " ~ request.name);
            rest = rest[sent .. $];
        }
        ptrdiff_t end;
        while ((end = pending.indexOf("\r\n\r\n")) < 0)
            fill(request.name);
        const head = pending[0 .. end + 4].toLower;
        size_t length;
        const field = head.indexOf("\r\ncontent-length:");
        if (field >= 0 && !request.head)
        {
            auto value = head[field + 17 .. $];
            value = value[0 .. value.indexOf("\r\n")];
            import std.string : strip;

            length = value.strip.to!size_t;
        }
        const chunked = head.indexOf("transfer-encoding: chunked") >= 0 && !request.head;
        if (chunked)
            while (!lastChunk(pending[end + 4 .. $]))
                fill(request.name);
        else
            while (pending.length < end + 4 + length)
                fill(request.name);
        const consumed = chunked ? end + 4 + pending[end + 4 .. $].indexOf("0\r\n\r\n") + 5 : end + 4 + length;
        pending = pending[consumed .. $].dup;
        if (head.indexOf("\r\nconnection: close") >= 0)
        {
            socket.close();
            socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
            pending = null;
        }
    }

    private void fill(string name)
    {
        char[4096] buffer;
        const received = socket.receive(buffer[]);
        assert(received > 0, "the connection closed during " ~ name);
        pending ~= buffer[0 .. received];
    }
}

/// Whether a chunked body is complete: it ends with the zero-length chunk.
private bool lastChunk(const(char)[] body) pure
{
    import std.string : indexOf;

    return
    body.indexOf("0\r\n\r\n") == 0 || body.indexOf("\r\n0\r\n\r\n") >= 0;
}

/// The server threads' allocations across `request` followed by `fence`.
private Allocations window(ref Client client, ref const Exchange request, ref const Exchange fence)
{
    Allocations before, after;
    assert(otherThreadsAllocations(before));
    client.exchange(request);
    client.exchange(fence);
    assert(otherThreadsAllocations(after));
    return Allocations(after.count - before.count, after.bytes - before.bytes);
}

/// The smaller of each field.
private Allocations least(Allocations a, Allocations b) pure nothrow @nogc
{
    return Allocations(a.count < b.count ? a.count : b.count, a.bytes < b.bytes ? a.bytes : b.bytes);
}

@("gs-rest-service: GC allocations and bytes per request stay within policy/request-allocations.json")
unittest
{
    import std.conv : to;
    import std.file : readText;
    import std.process : environment;

    const recording = environment.get("FLINT_REQUEST_ALLOCATIONS") == "record";
    Exchange[] requests;
    foreach (request; parseJSON(readText(requestsPath))["requests"].arrayNoRef)
        requests ~= exchangeOf(request);
    const budgets = recording ? JSONValue.init : parseJSON(readText(budgetsPath))["apps"][app]["requests"];

    assert(installAllocationCounter(), "the counter wraps druntime's collector, before any server thread starts");
    scope (exit)
        uninstallAllocationCounter();
    Allocations clientBefore;
    assert(thisThreadAllocations(clientBefore));
    const druntimeBefore = GC.stats().allocatedInCurrentThread;

    auto context = cast(ServletWebServerApplicationContext) FlintApplication.run!RestServiceApplication(
            ["--server.port=0", "--server.flint.threads=1"]);
    assert(context !is null, "gs-rest-service runs a servlet web server");
    scope (exit)
        context.close();
    const port = cast(ushort) context.getWebServer().getPort();
    auto client = Client(port);
    scope (exit)
        client.socket.close();

    const fence = exchangeOf(parseJSON(`{"name":"fence","method":"GET","path":"/greeting","headers":[],"body":null}`));
    foreach (_; 0 .. 2)
        foreach (ref request; requests)
            client.exchange(request);
    foreach (_; 0 .. 5)
        client.exchange(fence);

    auto pair = Allocations(ulong.max, ulong.max);
    foreach (_; 0 .. 5)
        pair = least(pair, window(client, fence, fence));
    const fenceCost = Allocations(pair.count / 2, pair.bytes / 2);

    string[] failures;
    string measured = "{";
    foreach (ref request; requests)
    {
        auto cost = Allocations(ulong.max, ulong.max);
        foreach (_; 0 .. 3)
        {
            client.exchange(fence);
            const total = window(client, request, fence);
            cost = least(cost, Allocations(total.count - fenceCost.count, total.bytes - fenceCost.bytes));
        }
        measured ~= (measured.length > 1 ? ",\n " : "\n ") ~ JSONValue(request.name)
            .toString ~ ": {\"allocations\": " ~ cost.count.to!string ~ ", \"bytes\": " ~ cost.bytes.to!string ~ "}";
        if (recording)
            continue;
        assert(request.name in budgets.objectNoRef, request.name ~ " has no budget in policy/request-allocations.json");
        const budget = budgets[request.name];
        if (cost.count <= budget["allocations"].integer && cost.bytes <= budget["bytes"].integer)
            continue;
        recordAllocationSites(true);
        client.exchange(fence);
        client.exchange(request);
        client.exchange(fence);
        recordAllocationSites(false);
        string failure = request.name ~ ": " ~ cost.count.to!string ~ " allocations and "
            ~ cost.bytes.to!string ~ " bytes, over the budget of "
            ~ budget["allocations"].integer.to!string ~ " and " ~ budget["bytes"].integer.to!string
            ~ "; top sites (with two fences' " ~ (2 * fenceCost.count).to!string ~ " allocations):";
        foreach (site; topAllocationSites(10))
            failure ~= "\n    " ~ site;
        failures ~= failure;
    }
    if (recording)
    {
        import std.stdio : writeln;

        writeln("FLINT_REQUEST_ALLOCATIONS ", app, " (fence ", fenceCost.count, " allocations, ",
                fenceCost.bytes, " bytes)\n", measured, "\n}");
    }

    // The counter's bytes are druntime's own: on this thread both counted the same allocations.
    Allocations clientAfter;
    assert(thisThreadAllocations(clientAfter));
    assert(clientAfter.bytes - clientBefore.bytes == GC.stats().allocatedInCurrentThread - druntimeBefore,
            "the counter's bytes differ from druntime's allocatedInCurrentThread");
    assert(failures.length == 0, "requests over their allocation budget:\n" ~ failures.join("\n"));
}

private string join(string[] parts, string separator) pure
{
    string text;
    foreach (i, part; parts)
        text ~= (i ? separator : "") ~ part;
    return text;
}
