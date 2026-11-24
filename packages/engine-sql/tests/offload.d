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

    @("libpq readiness resumes the waiting fiber at once, not at the next millisecond poll")
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
        auto work = new RoundTrips;
        assert(work.pool.open(config).code == Status.ok);
        Context context;
        scope (exit)
            assert(work.pool.close(context).code == Status.ok);

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
        publishRoundTrips(work);
        scope (exit)
            publishRoundTrips(null);
        assert(owner.value.post(0, &startRoundTrips).code == Status.ok);
        const ran = owner.value.run();
        assert(ran.code == Status.ok, ran.message);
        // Waking on readiness, a local round trip takes tens of microseconds; resuming only at a 1 ms poll
        // deadline, 200 of them took at least 200 ms.
        assert(work.elapsedMicros >= 0 && work.elapsedMicros < roundTrips * 500,
                "SQL waits resumed at the poll deadline rather than on readiness");
    }
}

version (FlintNativeLibpq)
{
    private enum stressClients = 256;
    private enum stressRounds = 20;

    private __gshared Pool stressPool;
    private shared uint stressDone;
    private shared uint stressFailures;
    private shared long stressStart;
    private shared long stressElapsed;

    // SAFETY: The harness publishes the pool before the reactor starts and every fiber only copies the scalar handle.
    private Pool sharedStressPool() @trusted nothrow @nogc
    {
        return stressPool;
    }

    // SAFETY: Written once by the harness before the reactor starts.
    private void publishStressPool(Pool pool) @trusted nothrow @nogc
    {
        stressPool = pool;
    }

    private void leaseClient() nothrow @nogc
    {
        auto pool = sharedStressPool();
        Context context;
        foreach (_; 0 .. stressRounds)
        {
            auto lease = pool.acquire(context);
            if (!lease.ok())
            {
                atomicOp!"+="(stressFailures, 1u);
                break;
            }
            scope RequestArena arena;
            if (!lease.value.execute("SELECT 1", [], arena, context).ok())
                atomicOp!"+="(stressFailures, 1u);
            if (pool.release(lease.value).code != Status.ok)
                atomicOp!"+="(stressFailures, 1u);
        }
        if (atomicOp!"+="(stressDone, 1u) == stressClients)
        {
            atomicStore(stressElapsed, Deadline.afterMillis(0).monotonicNanoseconds - atomicLoad(stressStart));
            Reactor.current().stop();
        }
    }

    @("ten leases serve 256 fibers on two workers, each release waking the queue head at once")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        PoolOptions config;
        config.driver = Driver.postgres;
        config.connectionString = address;
        config.maxConnections = 10;
        config.maxWaiters = stressClients;
        Pool pool;
        assert(pool.open(config).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        publishStressPool(pool);

        ReactorOptions options;
        options.cores = 2;
        options.fiberPoolSize = stressClients / 2 + 8;
        auto owner = Reactor.create(options);
        assert(owner.ok(), owner.error.message);
        atomicStore(stressDone, 0u);
        atomicStore(stressFailures, 0u);
        foreach (client; 0 .. stressClients)
            assert(owner.value.post(client % 2, &leaseClient).code == Status.ok);
        atomicStore(stressStart, Deadline.afterMillis(0).monotonicNanoseconds);
        const ran = owner.value.run();
        assert(ran.code == Status.ok, ran.message);
        assert(atomicLoad(stressDone) == stressClients);
        assert(atomicLoad(stressFailures) == 0);
        // 5,120 handoffs at one per millisecond poll took at least 5 s.
        assert(atomicLoad(stressElapsed) < 2_500_000_000L, "lease handoffs waited for the waiters' polls");
        // Every lease came back: the full pool is acquirable again.
        auto again = pool.acquire(context);
        assert(again.ok());
        assert(pool.release(again.value).code == Status.ok);
    }
}
