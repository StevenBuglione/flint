module sql_contract_tests;

import flint.arena : Error, RequestArena, Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.engine.sql : Connection, Driver, Isolation, Pool, PoolOptions, Row, SqlValue, ValueKind, withTransaction;
import std.process : environment;

@safe:

// Engine-level programs compose their SQL drivers (performance playbook S-1); these tests use both.
shared static this()
{
    import flint.engine.sql : Driver, enable;

    cast(void) enable(Driver.sqlite);
    cast(void) enable(Driver.postgres);
}

private PoolOptions options(Driver driver, string address, uint size = 1)
{
    PoolOptions result;
    result.driver = driver;
    result.connectionString = address;
    result.maxConnections = size;
    return result;
}

private SqlValue stored(ref scope RequestArena arena, ValueKind kind, scope const(char)[] text) nothrow @nogc
{
    const item = arena.copyIn(cast(const(ubyte)[]) text);
    assert(item.ok());
    return SqlValue(kind, 0, 0, item.value);
}

private bool isText(ref scope RequestArena arena, SqlValue value, scope const(char)[] expected) nothrow @nogc
{
    bool equal;
    const status = arena.read(value.bytes, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        equal = bytes == cast(const(ubyte)[]) expected;
    });
    return status == Status.ok && equal;
}

private void exerciseValues(Driver driver, string path)
{
    auto setup = options(driver, path);
    Pool pool;
    const opened = pool.open(setup);
    assert(opened.code == Status.ok, opened.message);
    Context context;
    scope (exit)
        assert(pool.close(context).code == Status.ok);
    auto acquired = pool.acquire(context);
    assert(acquired.ok(), acquired.error.message);
    auto connection = acquired.value;
    auto copied = connection;
    scope (exit)
    {
        assert(pool.release(connection).code == Status.ok);
        assert(pool.release(copied).code == Status.notFound);
    }

    ubyte[8192] scratch;
    scope arena = RequestArena(scratch[]);
    const created = connection.execute(
            "CREATE TEMP TABLE values_test(n bigint, k text, b bytea, z bigint, f boolean)", [], arena, context);
    assert(created.ok(), created.error.message);

    const text = "' ; -- no SQL execution";
    const blob = "blob\0end";
    const SqlValue[5] params = [
        SqlValue.init, stored(arena, ValueKind.text, text), stored(arena, ValueKind.bytes, blob),
        SqlValue(ValueKind.int64, 0), SqlValue(ValueKind.boolean, 0)
    ];
    const insert = driver == Driver.postgres
        ? "INSERT INTO values_test VALUES($1,$2,$3,$4,$5)" : "INSERT INTO values_test VALUES(?,?,?,?,?)";
    const inserted = connection.execute(insert, params[], arena, context);
    assert(inserted.ok(), inserted.error.message);
    assert(inserted.value == 1);
    const SqlValue[5] empty = [
        SqlValue.init, stored(arena, ValueKind.text, ""), stored(arena, ValueKind.bytes, ""),
        SqlValue(ValueKind.int64, -4), SqlValue(ValueKind.boolean, 1)
    ];
    assert(connection.execute(insert, empty[], arena, context).ok());

    Row saved;
    uint seen;
    const read = connection.query("SELECT n,k,b,z,f FROM values_test ORDER BY z DESC", [], arena,
            context, (ref Row row) @safe nothrow @nogc {
        assert(row.columns() == 5);
        assert(row.value(5, arena).error.code == Status.invalidArgument);
        saved = row;
        const n = row.value(0, arena);
        const k = row.value(1, arena);
        const b = row.value(2, arena);
        const z = row.value(3, arena);
        const f = row.value(4, arena);
        assert(n.ok() && k.ok() && b.ok() && z.ok() && f.ok());
        assert(n.value.kind == ValueKind.null_);
        assert(k.value.kind == ValueKind.text && isText(arena, k.value, seen == 0 ? text : ""));
        assert(b.value.kind == ValueKind.bytes && isText(arena, b.value, seen == 0 ? blob : ""));
        assert(z.value.kind == ValueKind.int64 && z.value.integer == (seen == 0 ? 0 : -4));
        assert(f.value.kind == ValueKind.boolean && f.value.integer == (seen == 0 ? 0 : 1));
        ++seen;
        return Error.init;
    });
    assert(read.code == Status.ok, read.message);
    assert(seen == 2);
    assert(saved.columns() == 0);
    assert(saved.value(0, arena).error.code == Status.notFound);
    exerciseTextRules(driver, connection, arena, context);
    const multi = connection.execute("SELECT 1; SELECT 2", [], arena, context);
    assert(multi.error.code == Status.invalidArgument);
    assert(connection.execute("SELECT 1", [], arena, context).ok());
}

private void exerciseTextRules(Driver driver, ref Connection connection, ref scope RequestArena arena,
        ref Context context)
{
    if (driver == Driver.sqlite)
    {
        const rejected = connection.execute("PRAGMA journal_mode=WAL", [], arena, context);
        assert(rejected.error.code == Status.permissionDenied);
    }
    const nulText = stored(arena, ValueKind.text, "early\0late");
    const identity = driver == Driver.sqlite ? "SELECT ?" : "SELECT $1::text";
    const withNull = connection.query(identity, [nulText], arena, context, (ref Row row) @safe nothrow @nogc {
        const found = row.value(0, arena);
        assert(found.ok() && found.value.kind == ValueKind.text && isText(arena, found.value, "early\0late"));
        return Error.init;
    });
    assert(withNull.code == (driver == Driver.sqlite ? Status.ok : Status.invalidArgument));
}

private void exerciseTransaction(Driver driver, string address)
{
    Pool pool;
    assert(pool.open(options(driver, address)).code == Status.ok);
    Context context;
    scope (exit)
        assert(pool.close(context).code == Status.ok);
    auto acquired = pool.acquire(context);
    assert(acquired.ok());
    scope RequestArena arena;
    auto connection = acquired.value;
    assert(connection.execute("CREATE TEMP TABLE transaction_test(value bigint)", [], arena, context).ok());
    assert(pool.release(connection).code == Status.ok);

    const rejected = withTransaction(pool, Isolation.serializable, context, (ref Connection lease) @safe nothrow @nogc {
        assert(lease.execute("INSERT INTO transaction_test VALUES(11)", [], arena, context).ok());
        assert(lease.execute("INSERT INTO transaction_test VALUES(12)", [], arena, context).ok());
        const nested = withTransaction(pool, Isolation.readCommitted, context,
            (ref Connection nestedLease) @safe nothrow @nogc => Error.init);
        assert(nested.code == Status.conflict);
        return Error(Status.invalidArgument, "rollback requested by test");
    });
    assert(rejected.code == Status.invalidArgument);
    const committed = withTransaction(pool, Isolation.readCommitted, context,
            (ref Connection lease) @safe nothrow @nogc => lease.execute("INSERT INTO transaction_test VALUES(23)",
                [], arena, context).error);
    assert(committed.code == Status.ok, committed.message);
    acquired = pool.acquire(context);
    assert(acquired.ok());
    connection = acquired.value;
    scope (exit)
        assert(pool.release(connection).code == Status.ok);
    size_t rows;
    const read = connection.query("SELECT value FROM transaction_test", [], arena, context,
            (ref Row row) @safe nothrow @nogc {
        const value = row.value(0, arena);
        assert(value.ok() && value.value.integer == 23);
        ++rows;
        return Error.init;
    });
    assert(read.code == Status.ok && rows == 1);
}

private void exercisePrepared(Driver driver, string address)
{
    import std.conv : to;

    Pool pool;
    assert(pool.open(options(driver, address)).code == Status.ok);
    Context context;
    scope (exit)
        assert(pool.close(context).code == Status.ok);
    auto acquired = pool.acquire(context);
    assert(acquired.ok());
    auto lease = acquired.value;
    scope (exit)
        assert(pool.release(lease).code == Status.ok);
    scope RequestArena arena;
    assert(lease.execute("CREATE TEMP TABLE prepare_test(id bigint)", [], arena, context).ok());
    foreach (key; 0 .. 129)
    {
        const statement = "SELECT " ~ key.to!string;
        const fetched = lease.query(statement, [], arena, context, (ref Row row) @safe nothrow @nogc {
            const value = row.value(0, arena);
            assert(value.ok() && value.value.integer == key);
            return Error.init;
        });
        assert(fetched.code == Status.ok, fetched.message);
    }
    assert(lease.execute("SELECT 0", [], arena, context).ok());
    assert(lease.execute("SELECT * FROM prepare_test", [], arena, context).ok());
    assert(lease.execute("ALTER TABLE prepare_test ADD COLUMN added BIGINT", [], arena, context).ok());
    const changed = lease.execute("SELECT * FROM prepare_test", [], arena, context);
    assert(changed.ok() || changed.error.code == Status.unsupported);
}

private long scalar(ref Connection lease, scope const(char)[] statement, ref Context context) nothrow @nogc
{
    scope RequestArena arena;
    long output;
    const read = lease.query(statement, [], arena, context, (ref Row row) @safe nothrow @nogc {
        const value = row.value(0, arena);
        assert(value.ok() && value.value.kind == ValueKind.int64);
        output = value.value.integer;
        return Error.init;
    });
    assert(read.code == Status.ok, read.message);
    return output;
}

/++
`Connection.sendBefore`: BEGIN goes ahead of the next statement, which then runs inside the transaction.
PostgreSQL runs the first rounds' BEGIN on its own (nothing is prepared yet) and pipelines the later rounds;
SQLite always runs it on its own first. Failures and a statement refused before sending behave the same.
+/
private void exercisePreamble(Driver driver, string address)
{
    Pool pool;
    assert(pool.open(options(driver, address)).code == Status.ok);
    Context context;
    scope (exit)
        assert(pool.close(context).code == Status.ok);
    auto acquired = pool.acquire(context);
    assert(acquired.ok());
    auto lease = acquired.value;
    scope (exit)
        assert(pool.release(lease).code == Status.ok);
    scope RequestArena arena;
    assert(lease.execute("CREATE TEMP TABLE preamble_rows (x bigint)", [], arena, context).ok());
    foreach (round; 0 .. 4)
    {
        // Rolling back removes the row: the INSERT ran inside the transaction BEGIN opened.
        lease.sendBefore("BEGIN");
        assert(lease.execute("INSERT INTO preamble_rows VALUES (1)", [], arena, context).ok());
        assert(!lease.dropPreamble(), "the preamble stayed queued after it was sent");
        assert(lease.execute("ROLLBACK", [], arena, context).ok());
        assert(scalar(lease, "SELECT count(*) FROM preamble_rows", context) == round);
        // Ahead of a query with rows, then committed.
        lease.sendBefore("BEGIN");
        assert(scalar(lease, "SELECT count(*) FROM preamble_rows", context) == round);
        assert(lease.execute("INSERT INTO preamble_rows VALUES (2)", [], arena, context).ok());
        assert(lease.execute("COMMIT", [], arena, context).ok());
    }
    assert(scalar(lease, "SELECT count(*) FROM preamble_rows", context) == 4);

    // A statement that fails after BEGIN leaves the transaction to roll back, and the lease stays usable.
    lease.sendBefore("BEGIN");
    assert(!lease.execute("INSERT INTO preamble_missing VALUES (1)", [], arena, context).ok());
    assert(lease.execute("ROLLBACK", [], arena, context).ok());
    assert(scalar(lease, "SELECT count(*) FROM preamble_rows", context) == 4);
    // The same for a statement that prepares and then fails as it runs: the second time it goes in the pipeline.
    foreach (_; 0 .. 2)
    {
        lease.sendBefore("BEGIN");
        // SQLite divides by zero to NULL; PostgreSQL fails the statement.
        const divided = lease.execute("SELECT 1 / (x - x) FROM preamble_rows", [], arena, context);
        assert(driver == Driver.sqlite || !divided.ok());
        assert(lease.execute("ROLLBACK", [], arena, context).ok());
        assert(scalar(lease, "SELECT count(*) FROM preamble_rows", context) == 4);
    }

    // A statement refused before anything is sent leaves the preamble queued.
    lease.sendBefore("BEGIN");
    assert(!lease.execute("SELECT 1\0", [], arena, context).ok());
    assert(lease.dropPreamble(), "a statement that was never sent consumed the preamble");
    assert(!lease.dropPreamble());

    // A failing preamble fails the statement, which does not run.
    lease.sendBefore("BEGIN NONSENSE");
    assert(!lease.execute("INSERT INTO preamble_rows VALUES (3)", [], arena, context).ok());
    assert(scalar(lease, "SELECT count(*) FROM preamble_rows", context) == 4);
}

version (FlintNativeSqlite)
{
    @("SQLite typed values, explicit binding, statement boundaries and stale rows")
    unittest
    {
        exerciseValues(Driver.sqlite, ":memory:");
        exerciseTransaction(Driver.sqlite, ":memory:");
        exercisePrepared(Driver.sqlite, ":memory:");
        exercisePreamble(Driver.sqlite, ":memory:");
    }

    @("SQLite refuses an empty statement and the lease stays usable")
    unittest
    {
        Pool pool;
        assert(pool.open(options(Driver.sqlite, ":memory:", 1)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto acquired = pool.acquire(context);
        assert(acquired.ok());
        auto lease = acquired.value;
        scope (exit)
            assert(pool.release(lease).code == Status.ok);
        scope RequestArena arena;
        assert(!lease.execute("", [], arena, context).ok());
        assert(scalar(lease, "SELECT 5", context) == 5);
    }

    @("Sixteen live SQLite leases saturate and cannot be used after release")
    unittest
    {
        auto setup = options(Driver.sqlite, ":memory:", 16);
        setup.maxWaiters = 0;
        Pool pool;
        assert(pool.open(setup).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        Connection[16] leases;
        foreach (ref lease; leases)
        {
            const acquired = pool.acquire(context);
            assert(acquired.ok());
            lease = acquired.value;
        }
        assert(pool.acquire(context).error.code == Status.resourceExhausted);
        foreach (ref lease; leases)
            assert(pool.release(lease).code == Status.ok);
        auto acquired = pool.acquire(context);
        assert(acquired.ok());
        assert(pool.release(acquired.value).code == Status.ok);
    }

    private void contend(Pool* pool, uint rounds, bool* failed) nothrow
    {
        Context context;
        scope RequestArena arena;
        foreach (_; 0 .. rounds)
        {
            auto acquired = pool.acquire(context);
            if (!acquired.ok())
            {
                *failed = true;
                return;
            }
            auto lease = acquired.value;
            *failed |= !lease.execute("SELECT 1", [], arena, context).ok();
            *failed |= pool.release(lease).code != Status.ok;
        }
    }

    @("an exhausted pool hands a released lease to its queued waiter without a polling stall")
    @system unittest
    {
        import core.thread.osthread : Thread;
        import core.time : MonoTime;
        import std.conv : to;

        Pool pool;
        assert(pool.open(options(Driver.sqlite, ":memory:")).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        enum rounds = 200;
        bool firstFailed, secondFailed;
        const started = MonoTime.currTime;
        auto first = new Thread({ contend(&pool, rounds, &firstFailed); }).start();
        auto second = new Thread({ contend(&pool, rounds, &secondFailed); }).start();
        first.join();
        second.join();
        const elapsed = (MonoTime.currTime - started).total!"msecs";
        assert(!firstFailed && !secondFailed);
        // 400 one-connection handoffs take a few milliseconds; a 1–2 ms poll per handoff takes far longer.
        assertWallClock(elapsed < 100, "400 lease handoffs took " ~ elapsed.to!string
                ~ " ms (bound 100 ms; above it, queued waiters stall between handoffs)");
    }
}

version (FlintNativeLibpq)
{
    @("PostgreSQL typed values and live cancel drain with transaction reset")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        exerciseValues(Driver.postgres, address);
        exerciseTransaction(Driver.postgres, address);
        exercisePrepared(Driver.postgres, address);
        Pool pool;
        assert(pool.open(options(Driver.postgres, address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto acquired = pool.acquire(context);
        assert(acquired.ok());
        auto lease = acquired.value;
        scope (exit)
            assert(pool.release(lease).code == Status.ok);
        scope RequestArena arena;
        const originalBackend = scalar(lease, "SELECT pg_backend_pid()", context);
        assert(lease.execute("BEGIN", [], arena, context).ok());
        auto source = CancelSource.create(Context.init, Deadline.afterMillis(80));
        assert(source.ok());
        auto bounded = source.value.context();
        assert(lease.execute("SELECT pg_sleep(10)", [], arena, bounded).error.code == Status.timedOut);
        assert(pool.release(lease).code == Status.ok);
        acquired = pool.acquire(context);
        assert(acquired.ok());
        lease = acquired.value;
        assert(scalar(lease, "SELECT pg_backend_pid()", context) == originalBackend);
        assert(scalar(lease, "SELECT 123", context) == 123);
    }

    @("PostgreSQL answers an empty statement, the query JDBC drivers validate connections with")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        Pool pool;
        assert(pool.open(options(Driver.postgres, address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto acquired = pool.acquire(context);
        assert(acquired.ok());
        auto lease = acquired.value;
        scope (exit)
            assert(pool.release(lease).code == Status.ok);
        scope RequestArena arena;
        const empty = lease.execute("", [], arena, context);
        assert(empty.ok() && empty.value == 0);
        // An empty script is still refused, and the lease stays usable.
        assert(lease.executeScript("", context).code != Status.ok);
        assert(scalar(lease, "SELECT 5", context) == 5);
    }

    @("PostgreSQL prepares BEGIN, COMMIT and ROLLBACK once per connection instead of parsing them per transaction")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        Pool pool;
        assert(pool.open(options(Driver.postgres, address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto acquired = pool.acquire(context);
        assert(acquired.ok());
        auto lease = acquired.value;
        scope (exit)
            assert(pool.release(lease).code == Status.ok);
        scope RequestArena arena;
        foreach (_; 0 .. 3)
        {
            assert(lease.execute("BEGIN READ ONLY", [], arena, context).ok());
            assert(lease.execute("COMMIT", [], arena, context).ok());
            assert(lease.execute("BEGIN", [], arena, context).ok());
            assert(lease.execute("ROLLBACK", [], arena, context).ok());
        }
        // One server-side statement per distinct text, reused by every later transaction.
        assert(scalar(lease, "SELECT count(*) FROM pg_prepared_statements WHERE statement IN "
                ~ "('BEGIN READ ONLY', 'COMMIT', 'BEGIN', 'ROLLBACK')", context) == 4);
    }

    @("PostgreSQL reads oid and \"char\" columns, as pg_catalog queries return them")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        Pool pool;
        assert(pool.open(options(Driver.postgres, address)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto acquired = pool.acquire(context);
        assert(acquired.ok());
        auto lease = acquired.value;
        scope (exit)
            assert(pool.release(lease).code == Status.ok);
        assert(scalar(lease, "SELECT 'int4'::regtype::oid", context) == 23);
        assert(scalar(lease, "SELECT 4294967295::oid", context) == 4_294_967_295);
        ubyte[256] scratch;
        scope arena = RequestArena(scratch[]); // text cells are copied into the arena
        size_t rows;
        bool letterRead, letterIsB, emptyRead, emptyIsEmpty;
        int letterStatus, letterKind;
        // The callback only records: an assertion inside it would leave the operation open.
        const read = lease.query("SELECT 'b'::\"char\", ''::\"char\"", [], arena, context,
                (ref Row row) @safe nothrow @nogc {
            const letter = row.value(0, arena);
            const empty = row.value(1, arena);
            letterRead = letter.ok();
            letterStatus = cast(int) letter.error.code;
            letterKind = letterRead ? cast(int) letter.value.kind : -1;
            letterIsB = letterRead && letter.value.kind == ValueKind.text && isText(arena, letter.value, "b");
            emptyRead = empty.ok();
            emptyIsEmpty = emptyRead && empty.value.kind == ValueKind.text && isText(arena, empty.value, "");
            ++rows;
            return Error.init;
        });
        assert(read.code == Status.ok && rows == 1, read.message);
        // The cell is read, as text, before its value is compared.
        assert(letterRead, "status " ~ imported!"std.conv".to!string(letterStatus));
        assert(letterKind == cast(int) ValueKind.text, "kind " ~ imported!"std.conv".to!string(letterKind));
        assert(letterRead && letterIsB, "\"char\" 'b' was not read as the text b");
        assert(emptyRead && emptyIsEmpty, "\"char\" '' was not read as empty text");
    }

    @("PostgreSQL sends BEGIN with the next statement: alone until both are prepared, then pipelined")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        exercisePreamble(Driver.postgres, address);
    }

    @("PostgreSQL disconnect prevents reuse and surfaces a commit without acknowledgment")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        Pool pool;
        assert(pool.open(options(Driver.postgres, address, 2)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto killer = pool.acquire(context);
        assert(killer.ok());
        scope (exit)
            assert(pool.release(killer.value).code == Status.ok);
        scope RequestArena arena;
        uint calls;
        const outcome = withTransaction(pool, Isolation.readCommitted, context,
                (ref Connection lease) @safe nothrow @nogc {
            ++calls;
            const backend = scalar(lease, "SELECT pg_backend_pid()", context);
            const SqlValue[1] target = [SqlValue(ValueKind.int64, backend)];
            const terminated = killer.value.execute("SELECT pg_terminate_backend($1::int4, 250)",
                target[], arena, context);
            assert(terminated.ok(), terminated.error.message);
            return Error.init;
        });
        assert(outcome.code == Status.unavailable && outcome.message == "SQL commit outcome is unknown");
        // The ambiguous outcome is surfaced once; the framework never re-runs the transaction body.
        assert(calls == 1);
        assert(killer.value.execute("SELECT 42", [], arena, context).ok());
    }

    @("PostgreSQL reports a commit that the server turned into a rollback as a failure")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        Pool pool;
        assert(pool.open(options(Driver.postgres, address, 2)).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        auto setup = pool.acquire(context);
        assert(setup.ok());
        scope RequestArena arena;
        assert(setup.value.execute("CREATE TEMP TABLE IF NOT EXISTS flint_aborted_commit (n int8)",
                [], arena, context).ok());
        assert(pool.release(setup.value).code == Status.ok);
        const outcome = withTransaction(pool, Isolation.readCommitted, context,
                (ref Connection lease) @safe nothrow @nogc {
            scope RequestArena local;
            assert(lease.execute("INSERT INTO flint_aborted_commit VALUES (1)", [], local, context).ok());
            // The failed statement aborts the server transaction; the body still reports success.
            assert(!lease.execute("SELECT 1 / 0", [], local, context).ok());
            return Error.init;
        });
        assert(outcome.code == Status.conflict, "a commit answered with ROLLBACK was reported as success");
    }

}

private void exerciseBindInjection(Driver driver, string address)
{
    Pool pool;
    assert(pool.open(options(driver, address)).code == Status.ok);
    Context context;
    scope (exit)
        assert(pool.close(context).code == Status.ok);
    auto acquired = pool.acquire(context);
    assert(acquired.ok());
    auto lease = acquired.value;
    scope (exit)
        assert(pool.release(lease).code == Status.ok);
    ubyte[8192] scratch;
    scope arena = RequestArena(scratch[]);
    assert(lease.execute("CREATE TEMP TABLE injection_test(k text, b bytea)", [], arena, context).ok());
    static immutable string[5] payloads = [
        "x'); DROP TABLE injection_test; --", "' OR '1'='1", "/* comment */ SELECT 1",
        "; DELETE FROM injection_test;", "$1 ? :name"
    ];
    const insert = driver == Driver.postgres
        ? "INSERT INTO injection_test VALUES($1,$2)" : "INSERT INTO injection_test VALUES(?,?)";
    foreach (payload; payloads)
    {
        const SqlValue[2] params = [
            stored(arena, ValueKind.text, payload), stored(arena, ValueKind.bytes, "nul\0;'--")
        ];
        const inserted = lease.execute(insert, params[], arena, context);
        assert(inserted.ok() && inserted.value == 1, inserted.error.message);
    }
    // Every payload is stored verbatim, the table still exists and nothing was deleted.
    assert(scalar(lease, "SELECT count(*) FROM injection_test", context) == payloads.length);
    const match = driver == Driver.postgres
        ? "SELECT k, b FROM injection_test WHERE k = $1" : "SELECT k, b FROM injection_test WHERE k = ?";
    foreach (payload; payloads)
    {
        const SqlValue[1] key = [stored(arena, ValueKind.text, payload)];
        uint found;
        const read = lease.query(match, key[], arena, context, (ref Row row) @safe nothrow @nogc {
            const k = row.value(0, arena);
            const b = row.value(1, arena);
            assert(k.ok() && isText(arena, k.value, payload));
            assert(b.ok() && b.value.kind == ValueKind.bytes && isText(arena, b.value, "nul\0;'--"));
            ++found;
            return Error.init;
        });
        assert(read.code == Status.ok && found == 1, read.message);
    }
    // A tautology payload is compared as one literal value, not spliced into the predicate.
    const SqlValue[1] tautology = [stored(arena, ValueKind.text, "nobody' OR '1'='1")];
    uint matched;
    assert(lease.query(match, tautology[], arena, context, (ref Row row) @safe nothrow @nogc {
            ++matched;
            return Error.init;
        }).code == Status.ok);
    assert(matched == 0);
}

private void exerciseNullKinds(Driver driver, string address)
{
    Pool pool;
    assert(pool.open(options(driver, address)).code == Status.ok);
    Context context;
    scope (exit)
        assert(pool.close(context).code == Status.ok);
    auto acquired = pool.acquire(context);
    assert(acquired.ok());
    auto lease = acquired.value;
    scope (exit)
        assert(pool.release(lease).code == Status.ok);
    ubyte[4096] scratch;
    scope arena = RequestArena(scratch[]);
    assert(lease.execute("CREATE TEMP TABLE null_kinds(id bigint, k text, b bytea, z bigint, f boolean)",
            [], arena, context).ok());
    const insert = driver == Driver.postgres
        ? "INSERT INTO null_kinds VALUES($1,$2,$3,$4,$5)" : "INSERT INTO null_kinds VALUES(?,?,?,?,?)";
    // Row 1 holds NULL in every column; row 2 holds the empty or zero value of each column's type.
    const SqlValue[5] nulls = [
        SqlValue(ValueKind.int64, 1), SqlValue.init, SqlValue.init, SqlValue.init, SqlValue.init
    ];
    const SqlValue[5] empties = [
        SqlValue(ValueKind.int64, 2), stored(arena, ValueKind.text, ""),
        stored(arena, ValueKind.bytes, ""), SqlValue(ValueKind.int64, 0),
        SqlValue(ValueKind.boolean, 0)
    ];
    assert(lease.execute(insert, nulls[], arena, context).ok());
    assert(lease.execute(insert, empties[], arena, context).ok());
    static immutable ValueKind[4] emptyKinds = [
        ValueKind.text, ValueKind.bytes, ValueKind.int64, ValueKind.boolean
    ];
    uint rows;
    const read = lease.query("SELECT id, k, b, z, f FROM null_kinds ORDER BY id", [], arena,
            context, (ref Row row) @safe nothrow @nogc {
        const id = row.value(0, arena);
        assert(id.ok());
        foreach (column; 1 .. 5)
        {
            const cell = row.value(column, arena);
            assert(cell.ok());
            if (id.value.integer == 1)
                assert(cell.value.kind == ValueKind.null_);
            else
            {
                assert(cell.value.kind == emptyKinds[column - 1]);
                assert(cell.value.integer == 0);
                if (cell.value.kind == ValueKind.text || cell.value.kind == ValueKind.bytes)
                    assert(isText(arena, cell.value, ""));
            }
        }
        ++rows;
        return Error.init;
    });
    assert(read.code == Status.ok && rows == 2, read.message);
    // The database itself distinguishes each NULL from the empty value of that type.
    assert(scalar(lease,
            "SELECT count(*) FROM null_kinds WHERE k IS NULL AND b IS NULL AND z IS NULL AND f IS NULL", context) == 1);
    assert(scalar(lease, "SELECT count(*) FROM null_kinds WHERE k = '' AND z = 0 AND f = false", context) == 1);
}

version (FlintNativeSqlite)
{
    @("bind_injection: SQLite quote, comment, semicolon and NUL payloads stay data")
    unittest
    {
        exerciseBindInjection(Driver.sqlite, ":memory:");
    }

    @("value_nulls: SQLite NULL, empty text, empty blob, zero and false stay distinct")
    unittest
    {
        exerciseNullKinds(Driver.sqlite, ":memory:");
    }

    import core.thread.osthread : Thread;

    private struct Waiter
    {
        Pool* pool;
        Context context;
        Status outcome = Status.invalidArgument;
        uint exhaustedRetries;
    }

    /// Queued waits that reached the pool's 5 s bound (min(deadline, 5 s) by the specification). A
    /// slow or heavily loaded host can keep the saturation phase going that long; each such waiter
    /// re-queues, and while it is out its queue position is briefly free.
    private shared uint waiterTimeouts;

    private void queueForLease(Waiter* waiter) nothrow
    {
        import core.time : usecs;

        for (;;)
        {
            auto acquired = waiter.pool.acquire(waiter.context);
            // Until the probe reports a full queue, the probe itself may hold the last queue position.
            if (acquired.error.code == Status.resourceExhausted)
            {
                ++waiter.exhaustedRetries;
                Thread.sleep(50.usecs);
                continue;
            }
            if (acquired.error.code == Status.timedOut)
            {
                import core.atomic : atomicOp;

                atomicOp!"+="(waiterTimeouts, 1);
                continue;
            }
            waiter.outcome = acquired.error.code;
            if (acquired.ok())
            {
                auto lease = acquired.value;
                if (waiter.pool.release(lease).code != Status.ok)
                    waiter.outcome = Status.ioError;
            }
            return;
        }
    }

    private Thread startWaiter(Waiter* waiter) @system
    {
        return new Thread({ queueForLease(waiter); }).start();
    }

    /// Acquire once with a deadline (1 ms by default) and report the terminal status and its latency.
    private Status probe(ref Pool pool, out long micros, long deadlineMillis = 1)
    {
        import core.time : MonoTime;

        auto source = CancelSource.create(Context.init, Deadline.afterMillis(deadlineMillis));
        assert(source.ok());
        auto limited = source.value.context();
        const started = MonoTime.currTime;
        auto acquired = pool.acquire(limited);
        micros = (MonoTime.currTime - started).total!"usecs";
        assert(!acquired.ok());
        return acquired.error.code;
    }

    @("pool_saturation: 16 leases and 256 queued waiters stay bounded, waiter 257 fails and cancelled waiters leave")
    @system unittest
    {
        import core.time : MonoTime, msecs;
        import std.conv : to;

        auto setup = options(Driver.sqlite, ":memory:", 16);
        assert(setup.maxWaiters == 256);
        Pool pool;
        assert(pool.open(setup).code == Status.ok);
        Context context;
        scope (exit)
            assert(pool.close(context).code == Status.ok);
        Connection[16] leases;
        size_t held;
        // If a check fails, return the leases still held so the queued waiters finish and close
        // can complete; otherwise close would wait for them forever.
        scope (exit)
            foreach (ref lease; leases[0 .. held])
                pool.release(lease);
        foreach (ref lease; leases)
        {
            auto acquired = pool.acquire(context);
            assert(acquired.ok());
            lease = acquired.value;
            ++held;
        }

        import core.atomic : atomicLoad, atomicStore;

        atomicStore(waiterTimeouts, 0u);
        // A queue position freed by a waiter whose 5 s bound expired may be taken by a probe, or
        // retaken by that waiter; only then may a probe see the other outcome.
        bool boundExpired()
        {
            return atomicLoad(waiterTimeouts) != 0;
        }

        auto first = CancelSource.create(Context.init, Deadline.none());
        auto second = CancelSource.create(Context.init, Deadline.none());
        assert(first.ok() && second.ok());
        enum victimA = 17, victimB = 200;
        auto waiters = new Waiter[256];
        auto threads = new Thread[256];
        foreach (index, ref waiter; waiters)
        {
            waiter.pool = &pool;
            if (index == victimA)
                waiter.context = first.value.context();
            else if (index == victimB)
                waiter.context = second.value.context();
            threads[index] = startWaiter(&waiter);
        }

        // Waiter 257 is the probe: once every worker is queued it is rejected immediately. A probe
        // that times out held a queue position, and a waiter it turned away retries after a short
        // sleep; pause after each such probe, longer each time, so slow schedulers let that waiter
        // re-queue before the next probe takes the position again.
        long micros;
        const queued = MonoTime.currTime;
        Status status;
        uint pause = 1;
        while ((status = probe(pool, micros)) != Status.resourceExhausted)
        {
            assert(status == Status.timedOut);
            assert(MonoTime.currTime - queued < 30_000.msecs, "256 waiters never filled the queue");
            Thread.sleep(pause.msecs);
            if (pause < 64)
                pause *= 2;
        }
        assertWallClock(micros < 50_000, "full-queue rejection took " ~ micros.to!string ~ " us against 50000 us");
        // A full queue must reject without waiting. These probes get a long deadline so that a host
        // which deschedules this thread past a 1 ms deadline before acquire reaches the queue cannot
        // turn the rejection into a timeout; a probe that wrongly queued would wait out the deadline.
        foreach (attempt; 0 .. 8)
        {
            const repeated = probe(pool, micros, 10_000);
            assert(repeated == Status.resourceExhausted || (repeated == Status.timedOut && boundExpired()));
            assertWallClock(micros < 50_000, "full-queue rejection took " ~ micros.to!string ~ " us against 50000 us");
        }

        // Cancelled waiters return and withdraw their queue positions.
        first.value.cancel();
        second.value.cancel();
        threads[victimA].join();
        threads[victimB].join();
        assert(waiters[victimA].outcome == Status.cancelled);
        assert(waiters[victimB].outcome == Status.cancelled);
        const vacated = probe(pool, micros);
        assert(vacated == Status.timedOut || (vacated == Status.resourceExhausted && boundExpired()),
                "a cancelled waiter kept its queue position");

        foreach (ref lease; leases)
            assert(pool.release(lease).code == Status.ok);
        held = 0;
        foreach (index, thread; threads)
        {
            thread.join();
            if (index != victimA && index != victimB)
                assert(waiters[index].outcome == Status.ok,
                        "waiter " ~ index.to!string ~ " ended with " ~ waiters[index].outcome.to!string);
        }
        auto after = pool.acquire(context);
        assert(after.ok());
        assert(pool.release(after.value).code == Status.ok);
    }
}

version (FlintNativeLibpq)
{
    @("bind_injection and value_nulls: PostgreSQL payloads stay data and NULLs stay distinct")
    unittest
    {
        const address = environment.get("FLINT_SQL_PG_TEST_DSN");
        if (address.length == 0)
            return;
        exerciseBindInjection(Driver.postgres, address);
        exerciseNullKinds(Driver.postgres, address);
    }
}

/// Wall-clock bounds are enforced on native hardware. A lane that runs these tests under full-system
/// emulation sets `FLINT_EMULATED=1`, and the bound is then reported with its measurement instead of
/// asserted, because emulated syscalls and context switches cost milliseconds (ADR-017).
private void assertWallClock(bool within, lazy string measurement) @trusted
{
    import core.stdc.stdio : fflush, printf, stdout;
    import std.process : environment;

    if (environment.get("FLINT_EMULATED") == "1")
    {
        const text = measurement;
        printf("FLINT-EMULATED wall-clock bound %s: %.*s\n", within ? "met".ptr : "not met".ptr,
                cast(int) text.length, text.ptr);
        fflush(stdout);
        return;
    }
    assert(within, measurement);
}
