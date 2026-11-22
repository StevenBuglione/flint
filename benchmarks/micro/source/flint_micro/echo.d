/// Exercises echo and explicit final cancellation on the selected Linux reactor.
module flint_micro.echo;

import core.time : dur;
import flint.arena : Status;
import flint.conc : Context, Deadline;
import flint.reactor : Backend, Completion, ConnectionId, IoId, ListenOptions, Reactor, ReactorOptions;
import flint_bench_gc.sys.loopback : receiveAll, sendAll;
import flint_micro.sys.driver : joinDriver, startDriver, takeOwner;
import flint_micro.timing : BatchResult, Trial, timeTrial;
import std.socket : InternetAddress, SocketOption, SocketOptionLevel, TcpSocket;

@safe:

/// The fixed number of simultaneous loopback connections.
enum connectionCount = 4;
/// Every completed operation echoes exactly this many bytes.
enum payloadLength = 64;
private enum char control = 0xff;

private char[payloadLength] fixturePayload() pure nothrow @nogc
{
    char[payloadLength] data;
    foreach (index, ref value; data)
        value = cast(char)((index * 17 + 57) % 251);
    return data;
}

/// Deterministic fixed echo payload, distinct from the cancellation control byte.
enum echoPayload = fixturePayload();

private final class Engine
{
    Reactor reactor;
    Status runStatus = Status.unavailable;
    size_t cancelled;
    bool failed;

    private bool timerActive;
    private IoId[connectionCount] cancellations;

    void run() nothrow
    {
        try
            runStatus = reactor.run().code;
        catch (Exception)
            runStatus = Status.ioError;
    }

    void accepted(ConnectionId connection) nothrow @nogc
    {
        auto owner = Reactor.current();
        if (!owner.readWith(connection, payloadLength, Context.init, &read).ok())
            fail();
    }

    private void read(Completion completion, scope const(ubyte)[] incoming) nothrow @nogc
    {
        if (completion.status != Status.ok || !incoming.length)
        {
            fail();
            return;
        }
        if (incoming.length == 1 && incoming[0] == control)
        {
            armCancellation(completion.connection);
            return;
        }
        auto owner = Reactor.current();
        if (!owner.writeWith(completion.connection, incoming, Context.init, &written).ok())
            fail();
    }

    private void written(Completion completion) nothrow @nogc
    {
        if (completion.status == Status.ok)
            accepted(completion.connection);
        else
            fail();
    }

    private void armCancellation(ConnectionId connection) nothrow @nogc
    {
        auto owner = Reactor.current();
        const pending = owner.readWith(connection, payloadLength, Context.init, &readCancelled);
        if (!pending.ok() || connection.slot >= cancellations.length)
        {
            fail();
            return;
        }
        cancellations[connection.slot] = pending.value;
        if (timerActive)
            return;
        timerActive = true;
        if (owner.postWith(owner.currentCore(), &cancelReaders).code != Status.ok)
            fail();
    }

    private void cancelReaders() nothrow @nogc
    {
        auto owner = Reactor.current();
        // Give the readiness/completion backend an event-loop turn to submit every pending read.
        if (owner.yieldUntil(Deadline.afterMillis(5)).code != Status.ok)
        {
            fail();
            return;
        }
        timerActive = false;
        foreach (ref ticket; cancellations)
        {
            if (!ticket.generation)
                continue;
            if (owner.cancel(ticket).code != Status.ok)
            {
                fail();
                return;
            }
            ticket = IoId.init;
        }
    }

    private void readCancelled(Completion completion, scope const(ubyte)[] incoming) nothrow @nogc
    {
        if (completion.status != Status.cancelled || incoming.length || completion.bytes != 0)
        {
            fail();
            return;
        }
        auto owner = Reactor.current();
        if (owner.close(completion.connection).code != Status.ok)
        {
            fail();
            return;
        }
        ++cancelled;
    }

    bool retired() const nothrow @nogc
    {
        const stats = reactor.workerStats(0);
        return !failed && cancelled == connectionCount && runStatus == Status.ok && stats.ok()
            && stats.value.outstandingOperations == 0;
    }

    private void fail() nothrow @nogc
    {
        failed = true;
        auto owner = Reactor.current();
        owner.stop();
    }
}

private final class Peers
{
    private TcpSocket[connectionCount] sockets;
    private int[connectionCount] descriptors;

    void open(ushort port)
    {
        foreach (index, ref peer; sockets)
        {
            peer = new TcpSocket;
            peer.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(2));
            peer.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"seconds"(2));
            peer.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
            peer.connect(new InternetAddress("127.0.0.1", port));
            descriptors[index] = peer.handle;
        }
    }

    void close()
    {
        foreach (peer; sockets)
        {
            if (peer !is null)
                peer.close();
        }
    }

    BatchResult exchange(uint rounds) nothrow @nogc
    {
        ulong checksum;
        char[payloadLength] output;
        foreach (_; 0 .. rounds)
        {
            foreach (fd; descriptors)
                if (!sendAll(fd, echoPayload[]))
                    return BatchResult.init;
            foreach (fd; descriptors)
            {
                if (!receiveAll(fd, output[]) || output[] != echoPayload[])
                    return BatchResult.init;
                checksum += cast(ubyte) output[0] + cast(ubyte) output[$ - 1] + payloadLength;
            }
        }
        return BatchResult(cast(ulong) rounds * descriptors.length, checksum);
    }

    bool cancel()
    {
        foreach (fd; descriptors)
            if (!sendAll(fd, [control]))
                return false;
        foreach (peer; sockets)
        {
            ubyte[1] byteValue;
            if (peer.receive(byteValue[]) != 0)
                return false;
        }
        return true;
    }
}

/// One independent trial, with connection setup, cancellation and draining outside the timed interval.
Trial echoTrial(bool smoke, out Backend backend)
{
    ReactorOptions options;
    options.cores = 1;
    options.maxConnectionsPerCore = connectionCount;
    options.maxPendingIoPerCore = connectionCount * 2 + 8;
    options.fiberPoolSize = 2;
    options.ioBufferBytes = payloadLength;
    options.maxTimersPerCore = 8;
    auto created = Reactor.create(options);
    if (!created.ok())
        return Trial.init;
    auto engine = new Engine;
    takeOwner(created.value, engine.reactor);
    backend = engine.reactor.activeBackend();
    if (backend != Backend.ioUring && backend != Backend.epoll)
        return Trial.init;
    if (engine.reactor.listenWith(ListenOptions("127.0.0.1", 0, 16), &engine.accepted).code != Status.ok)
        return Trial.init;
    const assigned = engine.reactor.localPort();
    if (!assigned.ok())
        return Trial.init;

    auto peers = new Peers;
    auto driver = startDriver(&engine.run);
    scope (failure)
    {
        engine.reactor.stop();
        cast(void) joinDriver(driver);
    }
    scope (exit)
        peers.close();
    peers.open(assigned.value);
    const timed = timeTrial(&peers.exchange, smoke ? 2 : 32, smoke);
    const cancelled = timed.result.count != 0 && peers.cancel();
    engine.reactor.stop();
    const joined = joinDriver(driver);
    return joined && cancelled && engine.retired() ? timed : Trial.init;
}
