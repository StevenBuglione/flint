module flint.engine.reactor.descriptor_poll_test;

// Reactor.awaitReadable: one-shot io_uring polls on borrowed descriptors (Linux).
version (linux)
{
    import core.sys.posix.sys.socket : AF_UNIX, SOCK_STREAM, socketpair;
    import core.sys.posix.unistd : close;
    import flint.arena : Status;
    import flint.conc : CancelSource, Context, Deadline;
    import flint.engine.reactor : Backend, Reactor, ReactorOptions;
    import flint.engine.reactor.test_support : readinessBackend;

    /// More waits than the owner's poll table holds, so every finished wait must free its entry.
    private enum reuseRounds = 600;

    // SAFETY: Test helper: writes one byte from a local to a socket the fixture owns until the test ends.
    private void put(int fd) @trusted nothrow @nogc
    {
        import core.sys.posix.sys.socket : send;

        const ubyte datum = 7;
        assert(send(fd, &datum, 1, 0) == 1);
    }

    // SAFETY: Test helper: reads into a local buffer from a socket the fixture owns until the test ends.
    private size_t take(int fd) @trusted nothrow @nogc
    {
        import core.sys.linux.sys.socket : MSG_DONTWAIT;
        import core.sys.posix.sys.socket : recv;

        ubyte[16] bytes;
        const got = recv(fd, bytes.ptr, bytes.length, MSG_DONTWAIT);
        return got > 0 ? cast(size_t) got : 0;
    }

    private long nowMillis() @safe nothrow @nogc
    {
        return Deadline.afterMillis(0).monotonicNanoseconds / 1_000_000;
    }

    private final class Fixture
    {
        int[2] pair = [-1, -1];
        int[2] idle = [-1, -1];
        bool sent;
        bool parkedForStop;
        bool finished;
        long readyAfterMillis;

        /// Task 0: each kind of wait in turn.
        void waiter() @safe nothrow @nogc
        {
            auto owner = Reactor.current();
            assert(owner.awaitReadable(-1, Deadline.afterMillis(10)).code == Status.invalidArgument);

            // Readable later: the writer sends after about 20 ms, and the poll's completion resumes this fiber.
            const began = nowMillis();
            assert(owner.awaitReadable(pair[0], Deadline.afterMillis(5_000)).code == Status.ok);
            assert(sent, "resumed before the descriptor was readable");
            readyAfterMillis = nowMillis() - began;
            assert(take(pair[0]) == 1);

            // Already readable: the poll completes at once.
            put(pair[1]);
            assert(owner.awaitReadable(pair[0], Deadline.afterMillis(5_000)).code == Status.ok);
            assert(take(pair[0]) == 1);

            // Nothing arrives: the deadline ends the wait, and the abandoned poll is cancelled.
            assert(owner.awaitReadable(idle[0], Deadline.afterMillis(20)).code == Status.timedOut);

            // The caller's context ends first.
            auto source = CancelSource.create(Context.init, Deadline.afterMillis(20));
            assert(source.ok);
            auto context = source.value.context();
            assert(owner.awaitReadable(idle[0], Deadline.afterMillis(5_000), context).code == Status.timedOut);

            // Every finished or abandoned wait frees its entry.
            foreach (_; 0 .. reuseRounds)
            {
                put(pair[1]);
                assert(owner.awaitReadable(pair[0], Deadline.afterMillis(5_000)).code == Status.ok);
                assert(take(pair[0]) == 1);
            }

            // The owner stops while this fiber waits: the wait reports it, and shutdown drains the poll.
            parkedForStop = true;
            assert(owner.awaitReadable(idle[0], Deadline.afterMillis(10_000)).code == Status.cancelled);
            finished = true;
        }

        /// Task 1: makes the first wait readable, then stops the owner once the waiter parks for the last time.
        void writer() @safe nothrow @nogc
        {
            auto owner = Reactor.current();
            assert(owner.yieldUntil(Deadline.afterMillis(20)).code == Status.ok);
            sent = true;
            put(pair[1]);
            while (!parkedForStop)
                cast(void) owner.yieldUntil(Deadline.afterMillis(1));
            cast(void) owner.yieldUntil(Deadline.afterMillis(20));
            owner.stop();
        }
    }

    @("a fiber parks on a borrowed descriptor until readable, its deadline or context, and shutdown drains the poll")
    @system unittest
    {
        ReactorOptions options;
        options.cores = 1;
        options.backend = Backend.ioUring;
        options.fiberPoolSize = 2;
        auto server = Reactor.create(options);
        if (!server.ok)
        {
            assert(server.error.code == Status.unsupported || server.error.code == Status.permissionDenied);
            return;
        }
        auto fixture = new Fixture;
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fixture.pair) == 0);
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fixture.idle) == 0);
        scope (exit)
            foreach (fd; fixture.pair ~ fixture.idle)
                close(fd);
        assert(server.value.awaitReadable(fixture.pair[0], Deadline.afterMillis(1)).code == Status.notFound);
        assert(server.value.postStartup(0, &fixture.waiter).code == Status.ok);
        assert(server.value.postStartup(0, &fixture.writer).code == Status.ok);
        assert(server.value.run().code == Status.ok);
        assert(fixture.finished);
        assert(fixture.readyAfterMillis >= 15 && fixture.readyAfterMillis < 1_000);
        const stats = server.value.workerStats(0);
        assert(stats.ok && stats.value.gcAllocated == 0);
        // The cancelled polls hold nothing: data arriving now reaches no one.
        put(fixture.idle[1]);
    }

    private final class Unsupported
    {
        int fd;
        Status status;

        void task() @safe nothrow @nogc
        {
            auto owner = Reactor.current();
            status = owner.awaitReadable(fd, Deadline.afterMillis(10)).code;
            owner.stop();
        }
    }

    @("an owner without io_uring reports descriptor polls unsupported, so callers use native watches")
    @system unittest
    {
        ReactorOptions options;
        options.cores = 1;
        options.backend = readinessBackend;
        options.fiberPoolSize = 1;
        auto server = Reactor.create(options);
        assert(server.ok, server.error.message);
        int[2] ends;
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, ends) == 0);
        scope (exit)
            foreach (fd; ends)
                close(fd);
        auto fixture = new Unsupported;
        fixture.fd = ends[0];
        assert(server.value.postStartup(0, &fixture.task).code == Status.ok);
        assert(server.value.run().code == Status.ok);
        assert(fixture.status == Status.unsupported);
    }
}
