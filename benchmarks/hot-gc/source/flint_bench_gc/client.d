/// Preallocated loopback peer for the canonical HTTP and barrier responses.
module flint_bench_gc.client;

import core.time : dur;
import flint_bench_gc.sys.loopback : receiveAll, sendAll;
import flint_bench_rest.profile : jsonBody;
import std.socket : InternetAddress, SocketOption, SocketOptionLevel, TcpSocket;

@safe:

private enum requestFields = " HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
private enum jsonRequest = "GET /json" ~ requestFields;
private enum barrierRequest = "GET /_flint_hot_gc_barrier" ~ requestFields;
private enum jsonResponse = "HTTP/1.1 200 OK\r\nContent-Length: 26\r\n"
    ~ "Content-Type: application/json\r\nConnection: keep-alive\r\n\r\n" ~ jsonBody;
private enum barrierHeader = "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n"
    ~ "Content-Type: text/plain\r\nConnection: keep-alive\r\n\r\n";

/// Discover a free numeric loopback port before creating the framework listener.
ushort choosePort()
{
    auto probe = new TcpSocket;
    scope (exit)
        probe.close();
    probe.bind(new InternetAddress("127.0.0.1", 0));
    return (cast(InternetAddress) probe.localAddress).port;
}

/// Startup-owned socket with fixed-value synchronous requests and responses.
struct Client
{
    private TcpSocket socket;
    private int fd;

    @disable this(this);

    /// Allocate a connection before either benchmark barrier.
    void open(ushort port)
    {
        socket = new TcpSocket;
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(2));
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"seconds"(2));
        socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
        socket.connect(new InternetAddress("127.0.0.1", port));
        fd = socket.handle;
    }

    /// Close a startup probe or a persistent connection after both barriers.
    void close()
    {
        if (socket !is null)
        {
            socket.close();
            socket = null;
        }
    }

    /// Execute and verify one full canonical response.
    bool json() nothrow @nogc
    {
        char[jsonResponse.length] response;
        return sendAll(fd, jsonRequest) && receiveAll(fd, response[]) && response[] == jsonResponse;
    }

    /// Read the current owner index and any sample taken by its barrier handler.
    uint barrier() nothrow @nogc
    {
        char[barrierHeader.length + 1] response;
        if (!sendAll(fd, barrierRequest) || !receiveAll(fd, response[]) || response[0 .. $ - 1] != barrierHeader)
            return uint.max;
        const owner = response[$ - 1];
        return owner >= '0' && owner <= '9' ? cast(uint)(owner - '0') : uint.max;
    }
}
