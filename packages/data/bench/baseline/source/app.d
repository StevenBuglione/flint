module app;

import flint.arena : Error, RequestArena, Status;
import flint.conc : Context;
import flint.sql : Pool, Row, RowConsumer, SqlValue, ValueKind;
import probe : benchmark, require, rows;

@safe:

private struct Record
{
    long id;
    long payload;
    long revision;
}

private alias Values = const(SqlValue)[];

private SqlValue integer(long number) pure nothrow @nogc
{
    return SqlValue(ValueKind.int64, number);
}

private void perform(ref Pool pool, scope const(char)[] sql, scope Values values, ref Context context,
        scope RowConsumer receive) nothrow @nogc
{
    auto leased = pool.acquire(context);
    require(leased.ok());
    scope (exit)
        require(pool.release(leased.value).code == Status.ok);
    scope RequestArena arena;
    if (receive is null)
        require(leased.value.execute(sql, values, arena, context).ok());
    else
        require(leased.value.query(sql, values, arena, context, receive).code == Status.ok);
}

private Record fetch(ref Pool pool, scope const(char)[] sql, scope Values values, ref Context context) nothrow @nogc
{
    Record result;
    bool seen;
    scope RequestArena arena;
    perform(pool, sql, values, context, (ref Row row) @safe nothrow @nogc {
        require(!seen && row.columns() == 3);
        const key = row.value(0, arena);
        const value = row.value(1, arena);
        const revision = row.value(2, arena);
        require(key.ok() && value.ok() && revision.ok());
        require(key.value.kind == ValueKind.int64 && value.value.kind == ValueKind.int64);
        require(revision.value.kind == ValueKind.int64);
        result = Record(key.value.integer, value.value.integer, revision.value.integer);
        seen = true;
        return Error.init;
    });
    require(seen);
    return result;
}

private bool exists(ref Pool pool, long id, ref Context context) nothrow @nogc
{
    bool present;
    enum sql = "SELECT 1 FROM probe_rows WHERE id=$1 LIMIT 1";
    perform(pool, sql, [integer(id)], context, (ref Row) @safe nothrow @nogc {
        present = true;
        return Error.init;
    });
    return present;
}

private ulong replay(ref Pool pool, ref Context context)
{
    perform(pool, "SELECT id, payload, revision FROM probe_rows WHERE 1=0", [], context,
            (ref Row) @safe nothrow @nogc => Error(Status.conflict));
    ulong checksum;
    foreach (value; 1 .. rows + 1)
    {
        const inserted = fetch(pool,
                "INSERT INTO probe_rows(payload,revision) VALUES($1,$2) RETURNING id,payload,revision",
                [integer(value), integer(0)], context);
        require(inserted.id > 0);
        const read = fetch(pool, "SELECT id,payload,revision FROM probe_rows WHERE id=$1 LIMIT 2",
                [integer(inserted.id)], context);
        require(read.payload == value && read.revision == 0);
        const updated = fetch(pool,
                "UPDATE probe_rows SET payload=$1,revision=revision+1 WHERE id=$2 AND revision=$3 "
                ~ "RETURNING id,payload,revision", [
                    integer(value + 1), integer(read.id), integer(read.revision)
        ], context);
        require(updated.payload == value + 1 && updated.revision == 1 && exists(pool, read.id, context));
        perform(pool, "DELETE FROM probe_rows WHERE id=$1", [integer(read.id)], context, null);
        require(!exists(pool, read.id, context));
        checksum += updated.payload + updated.revision;
    }
    return checksum;
}

void main(string[] args)
{
    benchmark(args, &replay);
}
