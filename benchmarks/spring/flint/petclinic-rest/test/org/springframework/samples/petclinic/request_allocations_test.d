/++
The per-request allocation gate for petclinic-rest (work-queue item 28, decisions 9a9aefa0;
policy/request-allocations.json). The method is gs-rest-service's (its test describes it): the app runs in-process
on the real servlet path, on druntime's collector behind flint.arena's allocation counter, and every suite request
(benchmarks/spring/suites/requests/petclinic-rest.json) is replayed over one keep-alive connection between fences.

petclinic-rest's requests change its database, so a request cannot be repeated for a minimum, and each pass needs
the data the suite expects. Before every pass the test drops and recreates the `public` schema through the app's
JdbcTemplate and restarts the app, whose SQL initialization loads the schema and data again. After a warm-up pass,
two measured passes run on fresh data, and each request keeps the smaller of its two costs, which takes out a rare
periodic allocation (a pool's housekeeping, say). The fence is an unknown path: a 404 that touches no data.

The database comes from POSTGRES_URL, POSTGRES_USER and POSTGRES_PASS, as for the side-by-side suite (CI starts a
disposable cluster: tools/ci.py request_allocation_tests).
+/
module org.springframework.samples.petclinic.request_allocations_test;

import core.memory : GC;
import flint.arena.gc : Allocations, installAllocationCounter, otherThreadsAllocations,
    recordAllocationSites, thisThreadAllocations, topAllocationSites, uninstallAllocationCounter;
import flint.boot : FlintApplication;
import flint.boot.web.server.servlet.context : ServletWebServerApplicationContext;
import flint.jdbc.core : JdbcTemplate;
import org.springframework.samples.petclinic : PetClinicApplication;
import std.json : JSONType, JSONValue, parseJSON;
import std.socket : InternetAddress, Socket, TcpSocket;

@safe:

private enum app = "petclinic-rest";
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

/// A running app and a client connected to it.
private struct Running
{
    ServletWebServerApplicationContext context;
    Client client;

    void stop()
    {
        client.socket.close();
        context.close();
    }
}

/// Start the app; without `initialize`, its SQL initialization is skipped, so it starts on a database a previous run
/// left in any state (its data.sql would collide with the rows already there).
private Running start(bool initialize = true)
{
    auto arguments = ["--server.port=0", "--server.flint.threads=1"];
    if (!initialize)
        arguments ~= "--flint.sql.init.mode=never";
    auto context = cast(ServletWebServerApplicationContext) FlintApplication.run!PetClinicApplication(arguments);
    assert(context !is null, "petclinic-rest runs a servlet web server");
    const port = cast(ushort) context.getWebServer().getPort();
    return Running(context, Client(port));
}

/// Drop the data, then start again: SQL initialization loads the suite's schema and data.
private Running fresh(ref Running running)
{
    auto jdbc = cast(JdbcTemplate) running.context.getBeanFactory().getBean("jdbcTemplate");
    assert(jdbc !is null, "petclinic-rest's JdbcTemplate");
    jdbc.execute("DROP SCHEMA public CASCADE");
    jdbc.execute("CREATE SCHEMA public");
    running.stop();
    return start();
}

/// One measured pass: each request's cost, less a fence's.
private Allocations[] pass(ref Client client, const(Exchange)[] requests, ref const Exchange fence)
{
    foreach (_; 0 .. 5)
        client.exchange(fence);
    auto pair = Allocations(ulong.max, ulong.max);
    foreach (_; 0 .. 5)
        pair = least(pair, window(client, fence, fence));
    const fenceCost = Allocations(pair.count / 2, pair.bytes / 2);
    Allocations[] costs;
    foreach (ref request; requests)
    {
        client.exchange(fence);
        const total = window(client, request, fence);
        costs ~= Allocations(total.count - fenceCost.count, total.bytes - fenceCost.bytes);
    }
    return costs;
}

@("petclinic-rest: GC allocations and bytes per request stay within policy/request-allocations.json")
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
    const fence = exchangeOf(parseJSON(
            `{"name":"fence","method":"GET","path":"/petclinic/allocation-fence",` ~ `"headers":[],"body":null}`));

    assert(installAllocationCounter(), "the counter wraps druntime's collector, before any server thread starts");
    scope (exit)
        uninstallAllocationCounter();
    Allocations clientBefore;
    assert(thisThreadAllocations(clientBefore));
    const druntimeBefore = GC.stats().allocatedInCurrentThread;

    auto running = start(false);
    scope (exit)
        running.stop();
    running = fresh(running);
    foreach (ref request; requests)
        running.client.exchange(request); // warm-up
    running = fresh(running);
    auto costs = pass(running.client, requests, fence);
    running = fresh(running);
    foreach (i, cost; pass(running.client, requests, fence))
        costs[i] = least(costs[i], cost);

    string[] failures;
    string measured = "{";
    foreach (i, ref request; requests)
    {
        const cost = costs[i];
        measured ~= (measured.length > 1 ? ",\n " : "\n ") ~ JSONValue(request.name)
            .toString ~ ": {\"allocations\": " ~ cost.count.to!string ~ ", \"bytes\": " ~ cost.bytes.to!string ~ "}";
        if (recording)
            continue;
        assert(request.name in budgets.objectNoRef, request.name ~ " has no budget in policy/request-allocations.json");
        const budget = budgets[request.name];
        if (cost.count <= budget["allocations"].integer && cost.bytes <= budget["bytes"].integer)
            continue;
        failures ~= request.name ~ ": " ~ cost.count.to!string ~ " allocations and "
            ~ cost.bytes.to!string ~ " bytes, over the budget of "
            ~ budget["allocations"].integer.to!string ~ " and " ~ budget["bytes"].integer.to!string;
    }
    if (failures.length)
    {
        // Name the sites on a fresh pass with recording on: the state each request expects is restored first.
        running = fresh(running);
        recordAllocationSites(true);
        foreach (ref request; requests)
            running.client.exchange(request);
        recordAllocationSites(false);
        failures ~= "top sites over the whole suite:";
        foreach (site; topAllocationSites(15))
            failures ~= "    " ~ site;
    }
    if (recording)
    {
        import std.stdio : writeln;

        writeln("FLINT_REQUEST_ALLOCATIONS ", app, "\n", measured, "\n}");
        // flint budget (tools/flint_budget.py) reads the costs from a file.
        const outPath = environment.get("FLINT_REQUEST_ALLOCATIONS_OUT");
        if (outPath.length)
        {
            import std.file : write;

            write(outPath, measured ~ "\n}\n");
        }
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
