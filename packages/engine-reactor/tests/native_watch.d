module flint.engine.reactor.native_watch_test;

// Linux epoll and io_uring, and macOS kqueue (ADR-024).
version (Posix)
{
    import core.atomic : atomicLoad, atomicOp, atomicStore;
    import core.sys.posix.sys.socket : AF_UNIX, SHUT_WR, SOCK_STREAM, send, shutdown, socketpair;
    import core.sys.posix.unistd : close;
    import flint.arena : Status;
    import flint.conc : Deadline;
    import flint.engine.reactor : Backend, NativeInterest, NativeReadyFn, Reactor, ReactorOptions;
    import flint.engine.reactor.test_support : readinessBackend;

    private shared int watched;
    private shared int quietFd;
    private shared uint observations;

    private NativeReadyFn callback() @safe nothrow @nogc
    {
        return delegate void(int fd, NativeInterest events) @safe nothrow @nogc {
            onReady(fd, events);
        };
    }

    private void ownerTask() @safe nothrow @nogc
    {
        auto reactor = Reactor.current();
        const fd = atomicLoad(watched);
        assert(reactor.watchNative(-1, NativeInterest.read, callback()).code == Status.invalidArgument);
        assert(reactor.watchNative(fd, NativeInterest.none, callback()).code == Status.invalidArgument);
        assert(reactor.watchNative(fd, NativeInterest.write, callback()).code == Status.ok);
        assert(reactor.watchNative(fd, NativeInterest.read, callback()).code == Status.ok);
        assert(reactor.watchNative(atomicLoad(quietFd), NativeInterest.read, callback())
                .code == Status.resourceExhausted);
        assert(reactor.yieldUntil(Deadline.afterMillis(30)).code == Status.ok);
        assert(atomicLoad(observations) == 1);
        reactor.stop();
    }

    private void onReady(int fd, NativeInterest events) @safe nothrow @nogc
    {
        auto reactor = Reactor.current();
        assert(reactor.currentCore == 0);
        assert(reactor.currentTask().error.code == Status.notFound);
        assert(fd == atomicLoad(watched));
        assert((events & NativeInterest.read) != 0 && (events & NativeInterest.error) != 0);
        assert((events & NativeInterest.write) == 0);
        assert(reactor.unwatchNative(fd).code == Status.ok);
        assert(reactor.unwatchNative(fd).code == Status.ok);
        assert(reactor.watchNative(atomicLoad(quietFd), NativeInterest.read, callback()).code == Status.ok);
        atomicOp!"+="(observations, 1);
    }

    private void exercise(Backend backend) @system
    {
        ReactorOptions options;
        options.cores = 1;
        options.backend = backend;
        options.fiberPoolSize = 1;
        options.maxNativeWatchesPerCore = 1;
        options.completionsPerTick = 1;
        auto server = Reactor.create(options);
        if (backend == Backend.ioUring && !server.ok)
        {
            assert(server.error.code == Status.unsupported || server.error.code == Status.permissionDenied);
            return;
        }
        assert(server.ok, server.error.message);

        int[2] ready;
        int[2] quiet;
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, ready) == 0);
        scope (exit)
            foreach (fd; ready)
                close(fd);
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, quiet) == 0);
        scope (exit)
            foreach (fd; quiet)
                close(fd);
        const ubyte datum = 42;
        assert(send(ready[1], &datum, 1, 0) == 1);
        assert(shutdown(ready[1], SHUT_WR) == 0);

        atomicStore(watched, ready[0]);
        atomicStore(quietFd, quiet[0]);
        atomicStore(observations, 0U);
        assert(server.value.watchNative(ready[0], NativeInterest.read, callback()).code == Status.conflict);
        assert(server.value.post(0, &ownerTask).code == Status.ok);
        assert(server.value.run().code == Status.ok);
        assert(atomicLoad(observations) == 1);
        const stats = server.value.workerStats(0);
        assert(stats.ok && stats.value.gcAllocated == 0);
        assert(send(quiet[0], &datum, 1, 0) == 1);
    }

    @("borrowed descriptors notify outside fibers and survive reactor shutdown")
    @system unittest
    {
        exercise(readinessBackend);
        version (FlintNativeLiburing)
            exercise(Backend.ioUring);
    }

    private enum tableWatches = 3;
    private shared int[tableWatches + 1] tableFds;
    private shared uint seenMask;

    private void onTableReady(int fd, NativeInterest) @safe nothrow @nogc
    {
        foreach (index; 0 .. tableWatches + 1)
            if (atomicLoad(tableFds[index]) == fd)
                atomicOp!"|="(seenMask, 1U << index);
        // Level-triggered: stop watching once seen, so the loop does not spin on it.
        assert(Reactor.current().unwatchNative(fd).code == Status.ok);
    }

    private NativeReadyFn tableCallback() @safe nothrow @nogc
    {
        return delegate void(int fd, NativeInterest events) @safe nothrow @nogc {
            onTableReady(fd, events);
        };
    }

    private void tableTask() @safe nothrow @nogc
    {
        auto reactor = Reactor.current();
        foreach (index; 0 .. tableWatches)
            assert(reactor.watchNative(atomicLoad(tableFds[index]), NativeInterest.read,
                    tableCallback()).code == Status.ok);
        const extra = atomicLoad(tableFds[tableWatches]);
        // Full: a new descriptor is refused, while updating a live watch needs no free entry.
        assert(reactor.watchNative(extra, NativeInterest.read, tableCallback()).code == Status.resourceExhausted);
        assert(reactor.watchNative(atomicLoad(tableFds[0]), NativeInterest.read, tableCallback()).code == Status.ok);
        // Removing a middle watch frees its entry for the next descriptor.
        assert(reactor.unwatchNative(atomicLoad(tableFds[1])).code == Status.ok);
        assert(reactor.unwatchNative(atomicLoad(tableFds[1])).code == Status.ok);
        assert(reactor.watchNative(extra, NativeInterest.read, tableCallback()).code == Status.ok);
        assert(reactor.yieldUntil(Deadline.afterMillis(30)).code == Status.ok);
        reactor.stop();
    }

    private void exerciseTable(Backend backend) @system
    {
        ReactorOptions options;
        options.cores = 1;
        options.backend = backend;
        options.fiberPoolSize = 1;
        options.maxNativeWatchesPerCore = tableWatches;
        auto server = Reactor.create(options);
        if (backend == Backend.ioUring && !server.ok)
            return;
        assert(server.ok, server.error.message);
        int[2][tableWatches + 1] pairs;
        foreach (index, ref pair; pairs)
        {
            assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
            atomicStore(tableFds[index], pair[0]);
            // Every descriptor is readable; only the watched ones may be reported.
            const ubyte datum = 7;
            assert(send(pair[1], &datum, 1, 0) == 1);
        }
        scope (exit)
            foreach (ref pair; pairs)
                foreach (fd; pair)
                    close(fd);
        atomicStore(seenMask, 0U);
        assert(server.value.post(0, &tableTask).code == Status.ok);
        assert(server.value.run().code == Status.ok);
        // Watches 0, 2 and the extra one; never the removed watch 1.
        assert(atomicLoad(seenMask) == 0b1101);
    }

    @("a full watch table refuses a new descriptor, updates a live one, and reuses a removed entry")
    @system unittest
    {
        exerciseTable(readinessBackend);
        version (FlintNativeLiburing)
            exerciseTable(Backend.ioUring);
    }
}
