/// Provider-independent repository operations with one exclusive lease per statement.
module flint.data.internal.repositories;

import flint.arena : Error, RequestArena, Result, Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.data.internal.mapper : encodeCell;
import flint.sql : Pool, Row, RowConsumer, SqlValue;

@safe:
package(flint.data):

private alias SqlParameters = const(SqlValue)[];

enum Mutation
{
    generated,
    explicitId,
    replace
}

void checkSchema(ref Pool pool, string sql, string table)
{
    auto deadline = CancelSource.create(Context.init, Deadline.afterMillis(5000));
    if (!deadline.ok())
        throw new Exception("could not prepare SQL repository startup deadline");
    auto context = deadline.value.context();
    scope RequestArena unused;
    const checked = query(pool, sql, [], unused, context,
            (ref Row) @safe nothrow @nogc => Error(Status.conflict, "unexpected SQL schema probe row"));
    if (checked.code != Status.ok)
        throw new Exception("could not verify SQL repository schema for " ~ table);
}

Error query(ref Pool pool, scope const(char)[] sql, scope const(SqlValue)[] parameters,
        ref scope RequestArena arena, ref Context context, scope RowConsumer consume) nothrow @nogc
{
    auto acquired = pool.acquire(context);
    if (!acquired.ok())
        return acquired.error;
    const outcome = acquired.value.query(sql, parameters, arena, context, consume);
    const released = pool.release(acquired.value);
    return outcome.code == Status.ok ? released : outcome;
}

Error execute(ref Pool pool, scope const(char)[] sql, SqlValue key, ref Context context) nothrow @nogc
{
    auto acquired = pool.acquire(context);
    if (!acquired.ok())
        return acquired.error;
    scope RequestArena unused;
    const outcome = acquired.value.execute(sql, [key], unused, context);
    const released = pool.release(acquired.value);
    return outcome.ok() ? released : outcome.error;
}

Error one(ref Pool pool, scope const(char)[] sql, scope SqlParameters parameters,
        ref scope RequestArena arena, ref Context context, scope RowConsumer consume) nothrow @nogc
{
    bool received;
    const outcome = query(pool, sql, parameters, arena, context, (ref Row row) @safe nothrow @nogc {
        if (received)
            return Error(Status.conflict, "SQL statement returned more than one row");
        received = true;
        return consume(row);
    });
    if (outcome.code != Status.ok)
        return outcome;
    return received ? Error.init : Error(Status.notFound, "SQL statement returned no row");
}

Result!bool exists(ref Pool pool, scope const(char)[] sql, SqlValue key, ref Context context) nothrow @nogc
{
    scope RequestArena ignored;
    bool found;
    const outcome = query(pool, sql, [key], ignored, context, (ref Row) @safe nothrow @nogc {
        found = true;
        return Error.init;
    });
    return Result!bool(found, outcome);
}

bool writtenAt(Mutation kind, bool id, bool revision) pure nothrow @nogc
{
    return kind == Mutation.replace ? !id && !revision : !id || kind == Mutation.explicitId;
}

Error encodeRevision(T)(scope const ref T revision, out SqlValue output) nothrow @nogc
{
    if (revision == T.max || revision == long.max)
        return Error(Status.invalidArgument, "SQL revision cannot be incremented");
    return encodeCell(revision, output);
}

Error namedParameters(Args, alias Bindings)(scope const ref Args arguments, scope SqlValue[] output) nothrow @nogc
{
    static foreach (ordinal, field; Bindings.order)
    {
        {
            const checked = encodeCell(arguments.tupleof[field], output[ordinal]);
            if (checked.code != Status.ok)
                return checked;
        }
    }
    return Error.init;
}
