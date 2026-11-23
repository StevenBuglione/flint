/// `ServerOptions.maxHandlers`: requests past the handler limit wait on their connections, in arrival order, and
/// start as handlers finish, as Tomcat's executor queues requests past `server.tomcat.threads.max`. None is
/// refused for want of a handler. `ServerOptions.acceptCount`: past the connection limit, new connections wait in
/// the listen backlog until a connection closes, as Tomcat leaves them past `maxConnections`.
module flint.engine.web.handler_limit;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.time : MonoTime, dur;
import flint.arena : Status;
import flint.conc : Context, Deadline;
import flint.engine.web.fiber : FiberResponse, FiberRoute;
import flint.engine.web.runtime : Server;
import flint.engine.web.types : Request, RequestContext, ServerOptions;
import std.socket : InternetAddress, Socket, SocketOption, SocketOptionLevel, TcpSocket, wouldHaveBlocked;

@safe:

/// The body `/hold` writes: far more than loopback socket buffers hold, so a client that does not read keeps the
/// handler suspended on write backpressure without blocking its worker.
private enum holdBytes = 64 * 1024 * 1024;

private final class Handlers
{
    shared int running;
    shared int mostRunning;
    shared int served;
    shared bool holding;

    void serve(ref scope Request request, ref scope RequestContext context, FiberResponse response)
    {
        // One worker runs every handler (cores = 1), so the high-water mark needs no compare-and-swap.
        const now = atomicOp!"+="(running, 1);
        if (now > atomicLoad(mostRunning))
            atomicStore(mostRunning, now);
        scope (exit)
            atomicOp!"-="(running, 1);
        // The two paths differ in length: "/hold" holds the handler, "/ok" answers at once.
        const hold = request.path().ok() && request.path().value.length() == "/hold".length;
        if (hold)
        {
            atomicStore(holding, true);
            assert(response.begin(200, null, holdBytes, context.cancellation).code == Status.ok);
            auto chunk = new ubyte[65_536];
            foreach (_; 0 .. holdBytes / chunk.length)
                if (response.send(chunk, context.cancellation).code != Status.ok)
                    return;
            return;
        }
        atomicOp!"+="(served, 1);
        // A client that gave up while its request waited is gone by now: its answer fails, as a servlet's does.
        cast(void) response.respond(200, null, cast(const(ubyte)[]) "ok", false, context.cancellation);
    }
}

private struct Fixture
{
    Server server;
    ushort port;
    Handlers handlers;

    void open(uint maxHandlers, uint connections, uint acceptCount = 1024)
    {
        ServerOptions options;
        options.port = 0;
        options.cores = 1;
        options.maxConnectionsPerCore = connections;
        options.maxHandlers = maxHandlers;
        options.acceptCount = acceptCount;
        options.http2 = false;
        options.idleTimeoutNanos = 60_000_000_000L;
        const started = server.start(options);
        assert(started.code == Status.ok, started.message);
        handlers = new Handlers;
        assert(server.routeFiber(FiberRoute(&handlers.serve)).code == Status.ok);
        port = server.listenPort();
        Context context;
        assert(server.poll(context).code == Status.ok);
    }

    void close()
    {
        server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);
    }

    Socket connect()
    {
        auto socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(10_000));
        return socket;
    }
}

private bool interrupted() @trusted
{
    import core.stdc.errno : EINTR, errno;

    return errno == EINTR;
}

private ptrdiff_t receiveSome(Socket socket, scope void[] buffer)
{
    for (;;)
    {
        const count = socket.receive(buffer);
        if (count != Socket.ERROR || !interrupted())
            return count;
    }
}

private void sendAll(Socket socket, scope const(char)[] text)
{
    const(ubyte)[] bytes = cast(const(ubyte)[]) text;
    while (bytes.length != 0)
    {
        const sent = socket.send(bytes);
        if (sent == Socket.ERROR && interrupted())
            continue;
        assert(sent > 0);
        bytes = bytes[sent .. $];
    }
}

/// One response's status line and body, framed by Content-Length.
private string exchange(Socket socket, scope const(char)[] path, out string status)
{
    sendAll(socket, "GET " ~ path ~ " HTTP/1.1\r\nHost: localhost\r\n\r\n");
    return readResponse(socket, status);
}

private string readResponse(Socket socket, out string status)
{
    char[] received;
    char[4096] chunk;
    for (;;)
    {
        for (size_t end = 0; end + 4 <= received.length; ++end)
        {
            if (received[end .. end + 4] != "\r\n\r\n")
                continue;
            const head = received[0 .. end];
            size_t length;
            for (size_t at = 0; at + 16 <= head.length; ++at)
                if (head[at .. at + 16] == "Content-Length: ")
                    foreach (c; head[at + 16 .. $])
                    {
                        if (c < '0' || c > '9')
                            break;
                        length = length * 10 + (c - '0');
                    }
            if (received.length >= end + 4 + length)
            {
                status = head[9 .. 12].idup;
                return received[end + 4 .. end + 4 + length].idup;
            }
            break;
        }
        const count = receiveSome(socket, chunk[]);
        assert(count > 0, "connection closed or timed out mid-response: " ~ received.idup);
        received ~= chunk[0 .. count];
    }
}

private void waitFor(lazy bool condition, string what) @trusted
{
    import core.thread : Thread;

    const deadline = MonoTime.currTime + dur!"seconds"(10);
    while (!condition)
    {
        assert(MonoTime.currTime < deadline, "timed out waiting until " ~ what);
        Thread.sleep(dur!"msecs"(1));
    }
}

private void pause(long milliseconds) @trusted
{
    import core.thread : Thread;

    Thread.sleep(dur!"msecs"(milliseconds));
}

@("max-handlers: requests past the limit queue on their connections, beyond the mailbox's 256, and none is refused")
unittest
{
    Fixture fixture;
    fixture.open(1, 512);
    scope (exit)
        fixture.close();

    // The only handler stays busy writing to a client that does not read yet.
    auto holder = fixture.connect();
    scope (exit)
        holder.close();
    sendAll(holder, "GET /hold HTTP/1.1\r\nHost: localhost\r\n\r\n");
    waitFor(atomicLoad(fixture.handlers.holding), "the holding handler runs");

    // More waiting requests than the worker's mailbox has entries (256 before this limit existed).
    enum waiting = 280;
    Socket[waiting] clients;
    foreach (ref client; clients)
    {
        client = fixture.connect();
        sendAll(client, "GET /ok HTTP/1.1\r\nHost: localhost\r\n\r\n");
    }
    scope (exit)
        foreach (client; clients)
            if (client !is null)
                client.close();
    pause(200);
    assert(atomicLoad(fixture.handlers.served) == 0, "a request started past the one-handler limit");

    // Ten clients give up while they wait: their connections leave the queue.
    foreach (index; 0 .. 10)
    {
        clients[index * 7].close();
        clients[index * 7] = null;
    }

    // Draining the held response frees the handler; every waiting request then runs, one at a time.
    char[65_536] sink;
    size_t drained;
    while (drained < holdBytes)
    {
        const count = receiveSome(holder, sink[]);
        assert(count > 0, "the held response ended early");
        drained += count;
    }
    foreach (client; clients)
    {
        if (client is null)
            continue;
        string status;
        const content = readResponse(client, status);
        assert(status == "200" && content == "ok", status ~ " " ~ content);
    }
    assert(atomicLoad(fixture.handlers.mostRunning) == 1);
    // A request whose client left may still run when its turn comes (Tomcat's queue does not notice either).
    const served = atomicLoad(fixture.handlers.served);
    assert(served >= waiting - 10 && served <= waiting);

    // The queue is empty again: a new request is served at once.
    auto late = fixture.connect();
    scope (exit)
        late.close();
    string status;
    assert(exchange(late, "/ok", status) == "ok" && status == "200");
}

@("max-handlers: a normal keep-alive load runs below the limit and is served as before")
unittest
{
    Fixture fixture;
    fixture.open(8, 64);
    scope (exit)
        fixture.close();
    Socket[6] clients;
    foreach (ref client; clients)
        client = fixture.connect();
    scope (exit)
        foreach (client; clients)
            client.close();
    foreach (round; 0 .. 50)
        foreach (client; clients)
        {
            string status;
            assert(exchange(client, "/ok", status) == "ok" && status == "200", status);
        }
    assert(atomicLoad(fixture.handlers.served) == 300);
    assert(atomicLoad(fixture.handlers.mostRunning) <= 6);
}

@("accept-count: past the connection limit a new connection waits in the backlog, and is served once a slot frees")
unittest
{
    Fixture fixture;
    fixture.open(8, 1, 4);
    scope (exit)
        fixture.close();

    // A keep-alive client holds the only connection slot.
    auto first = fixture.connect();
    string status;
    assert(exchange(first, "/ok", status) == "ok" && status == "200");

    // The kernel completes the next handshake into the backlog; the server does not take the connection yet,
    // so the request gets no answer, and the connection is neither closed nor reset.
    auto second = fixture.connect();
    scope (exit)
        second.close();
    sendAll(second, "GET /ok HTTP/1.1\r\nHost: localhost\r\n\r\n");
    second.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(300));
    ubyte[16] probe;
    const early = receiveSome(second, probe[]);
    assert(early == Socket.ERROR && wouldHaveBlocked(), "a connection past the limit was answered, closed or reset");
    assert(atomicLoad(fixture.handlers.served) == 1);

    // Closing the first frees the slot: the waiting connection is accepted and its request served.
    second.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(10_000));
    first.close();
    assert(readResponse(second, status) == "ok" && status == "200");
}
