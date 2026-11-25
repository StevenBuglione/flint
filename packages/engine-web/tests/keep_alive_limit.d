/// `maxKeepAliveRequests`, as Tomcat's: the response to a persistent connection's Nth request carries
/// `Connection: close` and the connection closes after it, for owner-loop and fiber routes alike, including requests
/// pipelined behind it.
module flint.engine.web.keep_alive_limit;

import core.time : dur;
import flint.arena : Result, Status;
import flint.conc : Context, Deadline;
import flint.engine.web.fiber : FiberResponse, FiberRoute;
import flint.engine.web.runtime : Server;
import flint.engine.web.stream : StreamField;
import flint.engine.web.types : Method, Request, RequestContext, Response, ServerOptions;
import std.socket : InternetAddress, Socket, SocketOption, SocketOptionLevel, TcpSocket;

@safe:

private final class Handlers
{
    Result!Response plain(ref scope Request request, ref scope RequestContext context) nothrow @nogc
    {
        auto body = context.arena.allocate(2, 1);
        if (!body.ok())
            return Result!Response(Response.init, body.error);
        cast(void) context.arena.write(body.value, (scope ubyte[] bytes) @safe nothrow @nogc {
            bytes[] = 'o';
        });
        return Result!Response(Response(200, "text/plain", body.value));
    }

    void fiber(ref scope Request request, ref scope RequestContext context, FiberResponse response)
    {
        const StreamField[1] type = [StreamField("Content-Type", "text/plain")];
        assert(response.respond(200, type[], cast(const(ubyte)[]) "fb", false, context.cancellation).code == Status.ok);
    }
}

private struct Fixture
{
    Server server;
    ushort port;

    void open(int limit)
    {
        ServerOptions options;
        options.port = 0;
        options.cores = 1;
        options.maxConnectionsPerCore = 16;
        options.http2 = false;
        options.maxKeepAliveRequests = limit;
        const started = server.start(options);
        assert(started.code == Status.ok, started.message);
        auto handlers = new Handlers;
        assert(server.route(Method.get, "/plain", &handlers.plain).code == Status.ok);
        assert(server.routeFiber(FiberRoute(&handlers.fiber)).code == Status.ok);
        port = server.listenPort();
        assert(port != 0);
        Context context;
        assert(server.poll(context).code == Status.ok);
    }

    void close()
    {
        server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);
    }

    Socket connect() @trusted
    {
        auto socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
        return socket;
    }
}

/// Reads whole responses (each with `Content-Length: 2`) from one socket, and its end.
private struct Reader
{
    Socket socket;
    char[] buffered;
    bool ended;

    /// The next response's head, or null once the peer has closed.
    string next() @trusted
    {
        import std.algorithm.searching : countUntil;

        for (;;)
        {
            const end = buffered.countUntil("\r\n\r\n");
            if (end >= 0 && buffered.length >= end + 4 + 2)
            {
                auto head = buffered[0 .. end].idup;
                buffered = buffered[end + 4 + 2 .. $].dup;
                return head;
            }
            char[4096] chunk;
            const got = socket.receive(chunk[]);
            if (got <= 0)
            {
                ended = true;
                assert(buffered.length == 0, "the peer closed part way through a response");
                return null;
            }
            buffered ~= chunk[0 .. got];
        }
    }
}

private bool closes(string head) pure
{
    import std.algorithm.searching : canFind;

    return head.canFind("\r\nConnection: close");
}

private void send(Socket socket, string path, size_t count = 1) @trusted
{
    string wire;
    foreach (_; 0 .. count)
        wire ~= "GET " ~ path ~ " HTTP/1.1\r\nHost: localhost\r\n\r\n";
    assert(socket.send(wire) == wire.length);
}

/// One request at a time: responses 1 to `limit - 1` keep the connection; the `limit`th closes it.
private void oneAtATime(ref Fixture fixture, string path, int limit) @trusted
{
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    auto reader = Reader(socket);
    foreach (index; 1 .. limit + 1)
    {
        send(socket, path);
        const head = reader.next();
        assert(head !is null, "the connection closed before its limit");
        assert(head[0 .. 13] == "HTTP/1.1 200 ");
        if (index < limit)
            assert(!closes(head), "a response before the limit closed the connection");
        else
            assert(closes(head), "the response at the limit did not carry Connection: close");
    }
    assert(reader.next() is null && reader.ended, "the connection stayed open after its limit");
}

@("the 100th response on a connection carries Connection: close and the socket closes; the 99th keeps it")
@trusted unittest
{
    Fixture fixture;
    fixture.open(100);
    scope (exit)
        fixture.close();
    oneAtATime(fixture, "/plain", 100);
    oneAtATime(fixture, "/fiber", 100);
}

@("requests pipelined past the limit are not answered: the connection closes after the limit's response")
@trusted unittest
{
    Fixture fixture;
    fixture.open(100);
    scope (exit)
        fixture.close();
    foreach (path; ["/plain", "/fiber"])
    {
        auto socket = fixture.connect();
        scope (exit)
            socket.close();
        send(socket, path, 101);
        auto reader = Reader(socket);
        size_t answered;
        string last;
        for (auto head = reader.next(); head !is null; head = reader.next())
        {
            ++answered;
            last = head;
            assert(answered == 100 || !closes(head));
        }
        assert(answered == 100 && closes(last), "pipelined requests were not cut at the limit");
    }
}

@("a limit of 1 closes after the first response, and zero or less serves without a limit")
@trusted unittest
{
    {
        Fixture fixture;
        fixture.open(1);
        scope (exit)
            fixture.close();
        oneAtATime(fixture, "/plain", 1);
        oneAtATime(fixture, "/fiber", 1);
    }
    foreach (unlimited; [0, -1])
    {
        Fixture fixture;
        fixture.open(unlimited);
        scope (exit)
            fixture.close();
        auto socket = fixture.connect();
        scope (exit)
            socket.close();
        auto reader = Reader(socket);
        foreach (_; 0 .. 150)
        {
            send(socket, "/plain");
            const head = reader.next();
            assert(head !is null && !closes(head));
        }
    }
}
