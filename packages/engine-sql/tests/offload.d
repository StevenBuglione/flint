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

version (FlintNativeLibpq)
{
    private void runFibers(uint cores, uint fibers, scope void function() @safe nothrow @nogc[] starts)
    {
        ReactorOptions options;
        options.cores = cores;
        options.fiberPoolSize = fibers;
        auto owner = Reactor.create(options);
        assert(owner.ok(), owner.error.message);
        foreach (index, start; starts)
            assert(owner.value.post(cast(uint)(index % cores), start).code == Status.ok);
        const ran = owner.value.run();
        assert(ran.code == Status.ok, ran.message);
    }

    private long nowNanos() nothrow @nogc
    {
        return Deadline.afterMillis(0).monotonicNanoseconds;
    }

    // ---- Ten leases, 256 fibers on two workers: each release hands its lease to the FIFO head at once.

    private enum stressClients = 256;
    private enum stressRounds = 20;

    private __gshared Pool stressPool;
    private shared uint stressDone;
    private shared uint stressFailures;
    private shared long stressStart;
    private shared long stressElapsed;

    // SAFETY: The harness publishes the scalar pool handle before the reactor starts; fibers only copy it.
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
            atomicStore(stressElapsed, nowNanos() - atomicLoad(stressStart));
            Reactor.current().stop();
        }
    }

    @("ten leases serve 256 fibers on two workers, each release handing its lease to the queue head at once")
    unittest
    {
        import std.process : environment;
        import flint.engine.sql.diagnostics : enableSqlDiagnostics, resetSqlDiagnostics, sqlDiagnostics;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        auto config = libpqPool(address);
        config.maxConnections = 10;
        config.maxWaiters = stressClients;
        Pool pool;
        assert(pool.open(config).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        publishStressPool(pool);
        enableSqlDiagnostics(true);
        scope (exit)
            enableSqlDiagnostics(false);
        resetSqlDiagnostics();
        atomicStore(stressDone, 0u);
        atomicStore(stressFailures, 0u);
        void function() @safe nothrow @nogc[stressClients] starts = &leaseClient;
        atomicStore(stressStart, nowNanos());
        runFibers(2, stressClients / 2 + 8, starts[]);
        assert(atomicLoad(stressDone) == stressClients);
        assert(atomicLoad(stressFailures) == 0);
        const counters = sqlDiagnostics();
        assert(counters.queuedAcquires > 0, "the test must queue waiters behind ten leases");
        // 5,120 acquisitions, most of them queued: with the head woken only by its 1 ms poll the handoffs
        // took several seconds.
        assert(atomicLoad(stressElapsed) < 1_500_000_000L, "lease handoffs waited for the head's poll");
        // Every lease came back: the full pool is acquirable again.
        auto again = pool.acquire(context);
        assert(again.ok());
        assert(pool.release(again.value).code == Status.ok);
    }

    // ---- A queued head whose deadline expires withdraws, and the next waiter still gets the lease at once.

    private final class Withdrawal
    {
        Pool pool;
        long releasedAt;
        long acquiredAt;
        Status expired = Status.ok;
        bool holderReady;
        bool headQueued;
    }

    private __gshared Withdrawal withdrawal;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join; one worker runs
    // every fiber, so the fields are never shared across threads.
    private Withdrawal sharedWithdrawal() @trusted nothrow @nogc
    {
        return withdrawal;
    }

    private void holder() nothrow @nogc
    {
        auto state = sharedWithdrawal();
        auto owner = Reactor.current();
        Context context;
        auto lease = state.pool.acquire(context);
        assert(lease.ok());
        state.holderReady = true;
        assert(owner.yieldUntil(Deadline.afterMillis(200)).code == Status.ok);
        state.releasedAt = nowNanos();
        assert(state.pool.release(lease.value).code == Status.ok);
    }

    private void expiringHead() nothrow @nogc
    {
        auto state = sharedWithdrawal();
        auto owner = Reactor.current();
        while (!state.holderReady)
            assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        auto source = CancelSource.create(Context.init, Deadline.afterMillis(50));
        assert(source.ok());
        auto limited = source.value.context();
        state.headQueued = true;
        state.expired = state.pool.acquire(limited).error.code;
    }

    private void patientWaiter() nothrow @nogc
    {
        auto state = sharedWithdrawal();
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();
        while (!state.headQueued)
            assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        Context context;
        auto lease = state.pool.acquire(context);
        assert(lease.ok());
        state.acquiredAt = nowNanos();
        assert(state.pool.release(lease.value).code == Status.ok);
    }

    // SAFETY: Written by the harness before the reactor starts and after all workers join.
    private void publishWithdrawal(Withdrawal state) @trusted nothrow @nogc
    {
        withdrawal = state;
    }

    @("a queued head that times out withdraws, and the waiter behind it gets the next release at once")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        auto state = new Withdrawal;
        assert(state.pool.open(libpqPool(address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(state.pool.close(context).code == Status.ok);
        publishWithdrawal(state);
        scope (exit)
            publishWithdrawal(null);
        runFibers(1, 8, [&holder, &expiringHead, &patientWaiter]);
        assert(state.expired == Status.timedOut, "the head's own deadline ends its wait");
        assert(state.acquiredAt >= state.releasedAt);
        // The release signals the new head; without it the waiter would sleep to its 100 ms fallback.
        assert(state.acquiredAt - state.releasedAt < 30_000_000L, "the waiter behind a withdrawn head waited");
    }

    // ---- A connection that dies mid-lease retires; its slot goes to the waiting fiber when retirement finishes.

    private final class Retirement
    {
        Pool pool;
        long releasedAt;
        long acquiredAt;
        bool holderReady;
        bool served;
    }

    private __gshared Retirement retirement;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join; one worker runs
    // every fiber.
    private Retirement sharedRetirement() @trusted nothrow @nogc
    {
        return retirement;
    }

    // SAFETY: Written by the harness before the reactor starts and after all workers join.
    private void publishRetirement(Retirement state) @trusted nothrow @nogc
    {
        retirement = state;
    }

    private void dyingHolder() nothrow @nogc
    {
        auto state = sharedRetirement();
        auto owner = Reactor.current();
        Context context;
        auto lease = state.pool.acquire(context);
        assert(lease.ok());
        state.holderReady = true;
        assert(owner.yieldUntil(Deadline.afterMillis(30)).code == Status.ok);
        scope RequestArena arena;
        // The server ends this session: the statement fails and the lease retires its connection.
        assert(!lease.value.execute("SELECT pg_terminate_backend(pg_backend_pid())", [], arena, context).ok());
        state.releasedAt = nowNanos();
        cast(void) state.pool.release(lease.value);
    }

    private void retirementWaiter() nothrow @nogc
    {
        auto state = sharedRetirement();
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();
        while (!state.holderReady)
            assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        Context context;
        auto lease = state.pool.acquire(context);
        assert(lease.ok(), lease.error.message);
        state.acquiredAt = nowNanos();
        scope RequestArena arena;
        state.served = lease.value.execute("SELECT 1", [], arena, context).ok();
        assert(state.pool.release(lease.value).code == Status.ok);
    }

    @("a connection that dies mid-lease retires, and its slot goes to the waiting fiber once retirement finishes")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        auto state = new Retirement;
        assert(state.pool.open(libpqPool(address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(state.pool.close(context).code == Status.ok);
        publishRetirement(state);
        scope (exit)
            publishRetirement(null);
        runFibers(1, 8, [&dyingHolder, &retirementWaiter]);
        assert(state.served, "the waiter's statement runs on a fresh connection");
        assert(state.acquiredAt >= state.releasedAt);
        assert(state.acquiredAt - state.releasedAt < 50_000_000L, "the freed slot waited for the fallback");
    }
}

version (FlintNativeLibpq)
{
    // ---- A leased connection keeps its watch between statements; readiness nobody waits for must not spin.

    private final class StrayReadiness
    {
        Pool pool;
        long idleCpuNanos = -1;
        bool listened, notified, servedAfter;
    }

    private __gshared StrayReadiness strayState;

    // SAFETY: The harness publishes before starting the reactor and clears after all workers join; one worker runs
    // every fiber.
    private StrayReadiness sharedStray() @trusted nothrow @nogc
    {
        return strayState;
    }

    // SAFETY: Written by the harness before the reactor starts and after all workers join.
    private void publishStray(StrayReadiness state) @trusted nothrow @nogc
    {
        strayState = state;
    }

    // SAFETY: clock_gettime writes one timespec into the local it is given.
    private long threadCpuNanos() @trusted nothrow @nogc
    {
        import core.sys.posix.time : CLOCK_THREAD_CPUTIME_ID, clock_gettime, timespec;

        timespec now;
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now);
        return now.tv_sec * 1_000_000_000L + now.tv_nsec;
    }

    private void listener() nothrow @nogc
    {
        auto state = sharedStray();
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();
        Context context;
        auto lease = state.pool.acquire(context);
        assert(lease.ok());
        scope RequestArena arena;
        state.listened = lease.value.execute("LISTEN flint_stray", [], arena, context).ok();
        while (!state.notified)
            assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        // The notification makes this lease's socket readable while no statement waits on it.
        const before = threadCpuNanos();
        assert(owner.yieldUntil(Deadline.afterMillis(100)).code == Status.ok);
        state.idleCpuNanos = threadCpuNanos() - before;
        state.servedAfter = lease.value.execute("SELECT 1", [], arena, context).ok();
        assert(state.pool.release(lease.value).code == Status.ok);
    }

    private void notifier() nothrow @nogc
    {
        auto state = sharedStray();
        auto owner = Reactor.current();
        while (!state.listened)
            assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
        Context context;
        auto lease = state.pool.acquire(context);
        assert(lease.ok());
        scope RequestArena arena;
        assert(lease.value.execute("NOTIFY flint_stray", [], arena, context).ok());
        assert(state.pool.release(lease.value).code == Status.ok);
        state.notified = true;
    }

    @("readiness on a leased connection between statements drops its watch instead of spinning the loop")
    unittest
    {
        import std.process : environment;

        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        auto state = new StrayReadiness;
        auto config = libpqPool(address);
        config.maxConnections = 2;
        assert(state.pool.open(config).code == Status.ok);
        Context context;
        scope (exit)
            assert(state.pool.close(context).code == Status.ok);
        publishStray(state);
        scope (exit)
            publishStray(null);
        runFibers(1, 8, [&listener, &notifier]);
        assert(state.listened && state.notified && state.servedAfter);
        // A loop reporting the readable socket on every pass would burn the whole 100 ms.
        assert(state.idleCpuNanos >= 0 && state.idleCpuNanos < 20_000_000L, "the idle worker spun on stray readiness");
    }
}
