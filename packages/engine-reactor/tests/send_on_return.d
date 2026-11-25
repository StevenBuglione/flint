/// A write a fiber queues leaves when that fiber returns to the loop, not after every other task of the same pass:
/// two tasks start in one pass, the first writes a response, and the second finds that response already at the
/// peer. With the writes started only at the end of the pass, the second task found nothing.
module flint.engine.reactor.send_on_return_test;

version (linux)
{
    import core.atomic : atomicLoad, atomicStore;
    import core.thread.osthread : Thread;
    import core.time : msecs;
    import flint.arena : Status;
    import flint.conc : Context;
    import flint.engine.reactor : Backend, Completion, ConnectionId, ListenOptions, Reactor, ReactorOptions;
    import flint.engine.reactor.test_support : readinessBackend;
    import std.socket : InternetAddress, TcpSocket;

    private enum responseBytes = 48;

    // SAFETY: Test helper: a non-blocking peek into a local buffer on a socket the test thread keeps open until the
    // reactor has stopped.
    private size_t waiting(int fd) @trusted nothrow @nogc
    {
        import core.sys.linux.sys.socket : MSG_DONTWAIT, MSG_PEEK;
        import core.sys.posix.sys.socket : recv;

        ubyte[responseBytes] bytes;
        const got = recv(fd, bytes.ptr, bytes.length, MSG_DONTWAIT | MSG_PEEK);
        return got > 0 ? cast(size_t) got : 0;
    }

    private final class Server
    {
        shared int firstPeer = -1;
        ConnectionId[2] connections;
        uint accepted;
        size_t seenBySecond = size_t.max;
        uint written;

        @safe nothrow @nogc void accept(ConnectionId id)
        {
            connections[accepted++] = id;
            if (accepted < 2)
                return;
            // Both tasks start in the next pass, one after the other.
            auto owner = Reactor.current();
            assert(owner.postWith(0, &respond).code == Status.ok);
            assert(owner.postWith(0, &check).code == Status.ok);
        }

        /// The first task: queue the response on the first connection and return to the loop.
        @safe nothrow @nogc void respond()
        {
            static immutable ubyte[responseBytes] response = 7;
            assert(Reactor.current().writeWith(connections[0], response[], Context.init, &wrote).ok);
        }

        /// The second task, in the same pass: the first task's response is already at its peer.
        @safe nothrow @nogc void check()
        {
            seenBySecond = waiting(atomicLoad(firstPeer));
            Reactor.current().stop();
        }

        @safe nothrow @nogc void wrote(Completion completion)
        {
            assert(completion.status == Status.ok || completion.status == Status.cancelled);
            ++written;
        }
    }

    private void exercise(Backend backend) @system
    {
        ReactorOptions options;
        options.backend = backend;
        options.cores = 1;
        options.fiberPoolSize = 2;
        auto server = Reactor.create(options);
        if (backend == Backend.ioUring && !server.ok)
        {
            assert(server.error.code == Status.unsupported || server.error.code == Status.permissionDenied);
            return;
        }
        assert(server.ok, server.error.message);
        auto fixture = new Server;
        assert(server.value.listenWith(ListenOptions("127.0.0.1", 0, 8), &fixture.accept).code == Status.ok);
        const port = server.value.localPort.value;

        auto first = new TcpSocket;
        auto second = new TcpSocket;
        scope (exit)
        {
            first.close();
            second.close();
        }
        auto peer = new Thread({
            first.connect(new InternetAddress("127.0.0.1", port));
            atomicStore(fixture.firstPeer, cast(int) first.handle);
            Thread.sleep(20.msecs);
            second.connect(new InternetAddress("127.0.0.1", port));
        }).start();
        const status = server.value.run();
        assert(status.code == Status.ok, status.message);
        assert(peer.join(false) is null);
        assert(fixture.seenBySecond == responseBytes, "the first task's response had not left when the second ran");
    }

    @("a fiber's queued write leaves when it returns to the loop, before the next task of the pass (epoll)")
    @system unittest
    {
        exercise(readinessBackend);
    }

    @("a fiber's queued write leaves when it returns to the loop, before the next task of the pass (io_uring)")
    @system unittest
    {
        version (FlintNativeLiburing)
            exercise(Backend.ioUring);
    }
}
