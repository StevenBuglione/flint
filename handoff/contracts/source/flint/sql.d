// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.sql;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
enum Driver : ubyte
{
    postgres,
    sqlite
}

enum Isolation : ubyte
{
    readCommitted,
    repeatableRead,
    serializable
}

enum ValueKind : ubyte
{
    null_,
    boolean,
    int64,
    float64,
    text,
    bytes
}

struct SqlValue
{
    ValueKind kind;
    long integer;
    double floating;
    Buffer bytes;
}

struct Transactional
{
    Isolation isolation = Isolation.readCommitted;
}

struct PoolOptions
{
    Driver driver = Driver.postgres;
    string connectionString;
    uint maxConnections = 16;
    uint maxWaiters = 256;
    long acquireTimeoutNanos = 5_000_000_000L;
    uint maxPreparedPerConnection = 128;
}

struct Row
{
    private ulong slot;
    private ulong generation;
    Result!SqlValue value(uint column, ref scope RequestArena arena) const nothrow @nogc;
    uint columns() const nothrow @nogc;
}

alias RowConsumer = Error delegate(ref Row row) @safe nothrow @nogc;
struct Connection
{
    private ulong slot;
    private ulong generation;
    Result!ulong execute(scope const(char)[] sql, scope const(SqlValue)[] params,
            ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error query(scope const(char)[] sql, scope const(SqlValue)[] params, ref scope RequestArena arena,
            ref Context context, scope RowConsumer consume) nothrow @nogc;
}

struct Pool
{
    private ulong slot;
    private ulong generation;
    Error open(PoolOptions options);
    Result!Connection acquire(ref Context context) nothrow @nogc;
    Error release(ref Connection connection) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

alias TransactionBody = Error delegate(ref Connection connection) @safe nothrow @nogc;
Error withTransaction(ref Pool pool, Isolation isolation, ref Context context, scope TransactionBody body) nothrow @nogc;
