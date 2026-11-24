module sql_offload_tests;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import flint.arena : RequestArena, Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.engine.reactor : Backend, Reactor, ReactorOptions;
import flint.engine.sql : Driver, Pool, PoolOptions;

@safe:

// Engine-level programs compose their SQL drivers (performance playbook S-1); these tests use both.
shared static this()
{
    import flint.engine.sql : Driver, enable;

    cast(void) enable(Driver.sqlite);
    cast(void) enable(Driver.postgres);
}

version (FlintNativeSqlite)
    version = FlintSqlReactorTest;
else version (FlintNativeLibpq)
    version = FlintSqlReactorTest;

version (FlintSqlReactorTest)
{
    import std.file : exists, remove, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    private shared uint beats;

    private void heartbeat() nothrow @nogc
    {
        atomicOp!"+="(beats, 1u);
        auto owner = Reactor.current();
        assert(owner.schedule(Deadline.afterMillis(2), &heartbeat).ok());
    }

    private final class BusyOwner
    {
        Pool pool;
        string statement;
        Status outcome;

        void exercise() nothrow @nogc
        {
            auto owner = Reactor.current();
            scope (exit)
                owner.stop();
            Context context;
            auto acquired = pool.acquire(context);
            assert(acquired.ok(), acquired.error.message);
            scope (exit)
                assert(pool.release(acquired.value).code == Status.ok);
            assert(owner.schedule(Deadline.afterMillis(2), &heartbeat).ok());
            auto source = CancelSource.create(Context.init, Deadline.afterMillis(80));
            assert(source.ok());
            auto limited = source.value.context();
            scope RequestArena arena;
            outcome = acquired.value.execute(statement, [], arena, limited).error.code;
        }
    }

    private __gshared BusyOwner testOwner;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join.
    private void publish(BusyOwner owner) @trusted nothrow @nogc
    {
        testOwner = owner;
    }

    // SAFETY: This fixture has one reactor owner and leaves its startup object rooted until run returns.
    private void startBusy() @trusted nothrow @nogc
    {
        testOwner.exercise();
    }

    private void boot(BusyOwner work)
    {
        atomicStore(beats, 0U);
        ReactorOptions options;
        version (OSX) // the readiness backend: kqueue on macOS, epoll on Linux (ADR-024)
            options.backend = Backend.kqueue;
        else version (Windows) // IOCP, the one Windows backend (ADR-026)
            options.backend = Backend.iocp;
        else
            options.backend = Backend.epoll;
        options.cores = 1;
        auto owner = Reactor.create(options);
        assert(owner.ok(), owner.error.message);
        publish(work);
        scope (exit)
            publish(null);
        assert(owner.value.post(0, &startBusy).code == Status.ok);
        const ran = owner.value.run();
        assert(ran.code == Status.ok, ran.message);
        assert(work.outcome == Status.timedOut);
        assert(atomicLoad(beats) >= 5);
    }

    version (FlintNativeSqlite) @("Busy SQLite uses a worker and permits reactor heartbeat during cancellation")
    unittest
    {
        const path = buildPath(tempDir(), "flint-sql-" ~ randomUUID().toString() ~ ".sqlite");
        scope (exit)
        {
            if (exists(path))
                remove(path);
        }
        PoolOptions config;
        config.driver = Driver.sqlite;
        config.connectionString = path;
        config.maxConnections = 2;
        auto work = new BusyOwner;
        work.statement = "INSERT INTO busy_test VALUES(2)";
        assert(work.pool.open(config).code == Status.ok);
        Context context;
        scope (exit)
            assert(work.pool.close(context).code == Status.ok);
        auto writer = work.pool.acquire(context);
        assert(writer.ok());
        scope (exit)
            assert(work.pool.release(writer.value).code == Status.ok);
        scope RequestArena arena;
        assert(writer.value.execute("CREATE TABLE busy_test(value INT)", [], arena, context).ok());
        assert(writer.value.execute("BEGIN IMMEDIATE", [], arena, context).ok());
        assert(writer.value.execute("INSERT INTO busy_test VALUES(1)", [], arena, context).ok());

        boot(work);
        assert(writer.value.execute("ROLLBACK", [], arena, context).ok());
    }

    version (FlintNativeLibpq) @("libpq socket progression and cancellation preserve owner reactor heartbeat")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        PoolOptions config;
        config.driver = Driver.postgres;
        config.connectionString = address;
        config.maxConnections = 1;
        auto work = new BusyOwner;
        work.statement = "SELECT pg_sleep(10)";
        assert(work.pool.open(config).code == Status.ok);
        Context context;
        scope (exit)
            assert(work.pool.close(context).code == Status.ok);
        boot(work);

        auto next = work.pool.acquire(context);
        assert(next.ok());
        scope (exit)
            assert(work.pool.release(next.value).code == Status.ok);
        scope RequestArena arena;
        assert(next.value.execute("SELECT 17", [], arena, context).ok());
    }
}

version (FlintNativeLibpq)
{
    private final class RoundTrips
    {
        Pool pool;
        long elapsedMicros = -1;

        void exercise() nothrow @nogc
        {
            import core.time : MonoTime;

            auto owner = Reactor.current();
            scope (exit)
                owner.stop();
            Context context;
            auto acquired = pool.acquire(context);
            assert(acquired.ok(), acquired.error.message);
            scope (exit)
                assert(pool.release(acquired.value).code == Status.ok);
            scope RequestArena arena;
            assert(acquired.value.execute("SELECT 1", [], arena, context).ok());
            const start = MonoTime.currTime;
            foreach (_; 0 .. roundTrips)
                assert(acquired.value.execute("SELECT 1", [], arena, context).ok());
            elapsedMicros = (MonoTime.currTime - start).total!"usecs";
        }
    }

    private enum roundTrips = 200;

    private __gshared RoundTrips roundTripOwner;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join.
    private void publishRoundTrips(RoundTrips owner) @trusted nothrow @nogc
    {
        roundTripOwner = owner;
    }

    // SAFETY: This fixture has one reactor owner and leaves its startup object rooted until run returns.
    private void startRoundTrips() @trusted nothrow @nogc
    {
        roundTripOwner.exercise();
    }

    private void runOnOneWorker(void function() @safe nothrow @nogc start)
    {
        ReactorOptions options;
        version (OSX)
            options.backend = Backend.kqueue;
        else version (Windows)
            options.backend = Backend.iocp;
        else
            options.backend = Backend.epoll;
        options.cores = 1;
        auto owner = Reactor.create(options);
        assert(owner.ok(), owner.error.message);
        assert(owner.value.post(0, start).code == Status.ok);
        const ran = owner.value.run();
        assert(ran.code == Status.ok, ran.message);
    }

    private PoolOptions libpqPool(string address)
    {
        PoolOptions config;
        config.driver = Driver.postgres;
        config.connectionString = address;
        config.maxConnections = 1;
        return config;
    }

    @("libpq readiness resumes the waiting fiber at once, not at the next millisecond poll, on reused descriptors too")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        // The second pass opens a new pool on a new reactor, so its connection usually reuses the first one's
        // descriptor number: no watch or signal may survive the first pass.
        foreach (pass; 0 .. 2)
        {
            auto work = new RoundTrips;
            assert(work.pool.open(libpqPool(address)).code == Status.ok);
            Context context;
            scope (exit)
                assert(work.pool.close(context).code == Status.ok);
            publishRoundTrips(work);
            scope (exit)
                publishRoundTrips(null);
            runOnOneWorker(&startRoundTrips);
            // Waking on readiness, a local round trip takes tens of microseconds; resuming only at a 1 ms poll
            // deadline, 200 of them took at least 200 ms.
            assert(work.elapsedMicros >= 0 && work.elapsedMicros < roundTrips * 500,
                    "SQL waits resumed at the poll deadline rather than on readiness");
        }
    }

    private enum delayedReplies = 10;
    private enum replyDelayMillis = 20;

    private final class DelayedReplies
    {
        Pool pool;
        long elapsedMicros = -1;

        void exercise() nothrow @nogc
        {
            import core.time : MonoTime;

            auto owner = Reactor.current();
            scope (exit)
                owner.stop();
            Context context;
            auto acquired = pool.acquire(context);
            assert(acquired.ok(), acquired.error.message);
            scope (exit)
                assert(pool.release(acquired.value).code == Status.ok);
            scope RequestArena arena;
            const start = MonoTime.currTime;
            foreach (_; 0 .. delayedReplies)
                assert(acquired.value.execute("SELECT pg_sleep(0.02)", [], arena, context).ok());
            elapsedMicros = (MonoTime.currTime - start).total!"usecs";
        }
    }

    private __gshared DelayedReplies delayedOwner;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join.
    private void publishDelayed(DelayedReplies owner) @trusted nothrow @nogc
    {
        delayedOwner = owner;
    }

    // SAFETY: This fixture has one reactor owner and leaves its startup object rooted until run returns.
    private void startDelayed() @trusted nothrow @nogc
    {
        delayedOwner.exercise();
    }

    @("a server that answers late wakes the waiting fiber when its reply arrives, not at the fallback deadline")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        auto work = new DelayedReplies;
        assert(work.pool.open(libpqPool(address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(work.pool.close(context).code == Status.ok);
        publishDelayed(work);
        scope (exit)
            publishDelayed(null);
        runOnOneWorker(&startDelayed);
        // Each reply is ready about 20 ms after its query; the fallback would make each wait last a second.
        assert(work.elapsedMicros >= delayedReplies * replyDelayMillis * 1_000, "a reply arrived before its delay");
        assert(work.elapsedMicros < delayedReplies * replyDelayMillis * 1_000 + 150_000,
                "a delayed reply waited for the fallback deadline");
    }

    private final class StoppedWhileWaiting
    {
        Pool pool;
        Status outcome = Status.ok;
        long elapsedMicros = -1;

        void exercise() nothrow @nogc
        {
            import core.time : MonoTime;

            auto owner = Reactor.current();
            Context context;
            auto acquired = pool.acquire(context);
            assert(acquired.ok(), acquired.error.message);
            scope (exit)
                cast(void) pool.release(acquired.value);
            assert(owner.schedule(Deadline.afterMillis(50), &stopOwner).ok());
            scope RequestArena arena;
            const start = MonoTime.currTime;
            // No deadline of its own: only the reactor stopping ends this wait.
            outcome = acquired.value.execute("SELECT pg_sleep(10)", [], arena, context).error.code;
            elapsedMicros = (MonoTime.currTime - start).total!"usecs";
        }
    }

    private void stopOwner() nothrow @nogc
    {
        Reactor.current().stop();
    }

    private __gshared StoppedWhileWaiting stoppedOwner;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join.
    private void publishStopped(StoppedWhileWaiting owner) @trusted nothrow @nogc
    {
        stoppedOwner = owner;
    }

    // SAFETY: This fixture has one reactor owner and leaves its startup object rooted until run returns.
    private void startStopped() @trusted nothrow @nogc
    {
        stoppedOwner.exercise();
    }

    @("stopping the reactor ends a libpq wait promptly, and the pool still serves afterwards")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        auto work = new StoppedWhileWaiting;
        assert(work.pool.open(libpqPool(address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(work.pool.close(context).code == Status.ok);
        publishStopped(work);
        scope (exit)
            publishStopped(null);
        runOnOneWorker(&startStopped);
        assert(work.outcome != Status.ok, "the statement cannot have finished its 10 s sleep");
        assert(work.elapsedMicros >= 0 && work.elapsedMicros < 2_000_000, "shutdown waited for the statement");

        auto next = work.pool.acquire(context);
        assert(next.ok(), next.error.message);
        scope (exit)
            assert(work.pool.release(next.value).code == Status.ok);
        scope RequestArena arena;
        assert(next.value.execute("SELECT 17", [], arena, context).ok());
    }
}
