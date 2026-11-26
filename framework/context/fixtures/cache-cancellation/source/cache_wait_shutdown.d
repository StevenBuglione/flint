module cache_wait_shutdown;

import core.atomic : atomicLoad, atomicStore;
import core.thread : Thread;
import core.time : dur;
import flint.arena : Status;
import flint.cache : Cache;
import flint.cache.concurrent : ConcurrentMapCache;
import flint.conc : Context, Deadline;
import flint.engine.aot.any : Any;
import flint.engine.reactor : Reactor;
import flint.engine.web.fiber : FiberResponse, FiberRoute;
import flint.engine.web.runtime : Server;
import flint.engine.web.types : Request, RequestContext, ServerOptions, ShutdownMode;
import flint.java.io : IOException;
import flint.java.lang : IllegalStateException;
import std.algorithm.searching : endsWith;
import std.socket : InternetAddress, Socket, SocketOption, SocketOptionLevel, TcpSocket;

@safe:

private final class Requests
{
    private Cache cache;
    private uint calls;
    shared bool loading;
    shared bool waiting;
    shared bool cancelled;

    this(bool usingCache)
    {
        if (usingCache)
            cache = new ConcurrentMapCache("shutdown");
    }

    void serve(ref scope Request, ref scope RequestContext context, FiberResponse response)
    {
        const call = ++calls;
        if (call == 3)
        {
            assert(response.respond(200, null, cast(const(ubyte)[]) "waiting", false,
                    context.cancellation).code == Status.ok);
            return;
        }

        if (cache is null)
        {
            auto owner = Reactor.current();
            assert(owner.armRemoteWake().ok());
            if (call == 1)
                atomicStore(loading, true);
            else
                atomicStore(waiting, true);
            const outcome = owner.yieldUntil(Deadline.afterMillis(ulong.max));
            assert(outcome.code == Status.cancelled);
            if (call == 2)
                atomicStore(cancelled, true);
            return;
        }

        if (call == 2)
            atomicStore(waiting, true);
        try
            cache.get(Any.of("same"), &load);
        catch (Cache.ValueRetrievalException failure)
            assert(call == 1 && cast(IOException) failure.getCause() !is null);
        catch (IOException)
        {
            assert(call == 2);
            atomicStore(cancelled, true);
        }
        catch (IllegalStateException)
            assert(call == 2);
    }

    private Any load()
    {
        auto owner = Reactor.current();
        assert(owner.armRemoteWake().ok());
        atomicStore(loading, true);
        const outcome = owner.yieldUntil(Deadline.afterMillis(ulong.max));
        assert(outcome.code == Status.cancelled);
        throw new IOException(outcome.message);
    }
}

private Socket sendRequest(ushort port)
{
    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
    enum readLimit = dur!"seconds"(5);
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, readLimit);
    enum query = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
    assert(socket.send(query) == query.length);
    return socket;
}

private string reply(Socket socket)
{
    scope (exit)
        socket.close();
    char[512] data;
    char[] content;
    for (;;)
    {
        auto length = socket.receive(data[]);
        assert(length >= 0);
        if (length == 0)
            return content.idup;
        content ~= data[0 .. length];
    }
}

private void awaitEntry(ref shared bool entered)
{
    const deadline = Deadline.afterMillis(5_000).monotonicNanoseconds;
    enum pollDelay = dur!"msecs"(1);
    while (!atomicLoad(entered))
    {
        assert(Deadline.afterMillis(0).monotonicNanoseconds < deadline);
        Thread.sleep(pollDelay);
    }
}

private void checkShutdown(bool usingCache)
{
    Server server;
    ServerOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    options.cores = 1;
    options.maxConnectionsPerCore = 16;
    options.http2 = false;
    options.shutdown = ShutdownMode.immediate;
    const opened = server.start(options);
    assert(opened.code == Status.ok, opened.message);
    auto requests = new Requests(usingCache);
    assert(server.routeFiber(FiberRoute(&requests.serve)).code == Status.ok);
    Context context;
    assert(server.poll(context).code == Status.ok);
    scope (failure)
        server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);

    const port = server.listenPort();
    auto first = sendRequest(port);
    scope (exit)
        first.close();
    awaitEntry(requests.loading);
    auto second = sendRequest(port);
    scope (exit)
        second.close();
    awaitEntry(requests.waiting);
    assert(reply(sendRequest(port)).endsWith("\r\n\r\nwaiting"));

    const stopped = server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);
    assert(stopped.code == Status.ok, stopped.message);
    assert(atomicLoad(requests.cancelled), "waiter did not propagate cancellation");
}

@("shutdown retires native fibers waiting without a cache")
unittest
{
    checkShutdown(false);
}

@("shutdown retires a native cache waiter with an I/O cancellation")
unittest
{
    checkShutdown(true);
}
