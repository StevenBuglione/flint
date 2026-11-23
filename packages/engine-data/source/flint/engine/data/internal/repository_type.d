/// Compile-time entity repositories with concrete allocation-free row assignment.
module flint.engine.data.internal.repository_type;

import flint.arena : Error, RequestArena, Result, Status;
import flint.conc : Context;
import flint.engine.data.internal.mapper : decodeRow, encodeCell, readField, readInt64, signed64;
import flint.engine.data.internal.queries : NamedQuery;
import flint.engine.data.internal.repositories : Mutation, checkSchema, encodeRevision, execute,
    exists, namedParameters, one, writtenAt;
import flint.engine.data.internal.schema : Entity, absent;
import flint.engine.data.internal.sqlgen : generate;
import flint.engine.sql : Pool, Row, SqlValue;

@safe:

private alias Values = const(SqlValue)[];
private alias Presence = Result!bool;

/// The allocation-free statement surface for an entity and identifier type.
interface CrudRepository(T, ID)
{
    private alias Outcome = Result!T;

    /// Fetch the sole row with this identifier.
    Outcome findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    /// Insert an unset identifier or update an existing identifier.
    Outcome save(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    /// Delete the identifier if present.
    Error deleteById(ID id, ref Context context) nothrow @nogc;
    /// Determine whether the identifier is present.
    Presence existsById(ID id, ref Context context) nothrow @nogc;
}

/// Repository backed by the pinned native SQL pool.
final class SqlRepository(T, ID) : CrudRepository!(T, ID)
{
    private Pool pool;
    private alias Mapping = Entity!T;
    private alias Arena = RequestArena;
    private alias Outcome = Result!T;
    private enum sql = generate(Mapping.table, Mapping.fields[], Mapping.id, Mapping.revision);

    static assert(is(ID == Mapping.Key), T.stringof ~ ": repository identifier type must match the Id field");

    /// Copy the pool's handle and validate the table and selected columns at startup.
    this(ref Pool source)
    {
        pool = source;
        checkSchema(pool, sql.schema, Mapping.table);
    }

    /// Fetch the sole mapped row and copy its data into the supplied arena.
    override Outcome findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc
    {
        SqlValue key;
        const checked = bindKey(id, key);
        if (checked.code != Status.ok)
            return Outcome(T.init, checked);
        return read(sql.find, [key], arena, context);
    }

    /// Insert an unset identifier or update an existing identifier.
    override Outcome save(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc
    {
        return write(entity, entity.tupleof[Mapping.id] == 0 ? Mutation.generated : Mutation.replace, arena, context);
    }

    /// Insert a new row with the entity's explicit, nonzero identifier.
    Outcome insert(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc
    {
        if (entity.tupleof[Mapping.id] == 0)
            return Outcome(T.init, Error(Status.invalidArgument, "explicit SQL insert requires a nonzero identifier"));
        return write(entity, Mutation.explicitId, arena, context);
    }

    private Outcome write(scope const ref T value, Mutation kind, ref scope Arena arena, ref Context ctx) nothrow @nogc
    {
        SqlValue[Mapping.fields.length] values;
        size_t count;
        const checked = bind(value, kind, values[], count);
        if (checked.code != Status.ok)
            return Outcome(T.init, checked);
        const text = kind == Mutation.replace ? sql.update : (kind == Mutation.generated
                ? sql.create : sql.explicitInsert);
        const saved = read(text, values[0 .. count], arena, ctx);
        static if (Mapping.revision != absent)
        {
            if (kind == Mutation.replace && saved.error.code == Status.notFound)
                return Outcome(T.init, Error(Status.conflict, "SQL revision no longer matches"));
        }
        if (kind == Mutation.generated && saved.ok() && saved.value.tupleof[Mapping.id] == 0)
            return Outcome(T.init, Error(Status.conflict, "SQL schema returned a zero generated identifier"));
        return saved;
    }

    private Error bind(scope const ref T entity, Mutation kind, scope SqlValue[] output, out size_t count) nothrow @nogc
    {
        static foreach (index, field; Mapping.fields)
        {
            static if (!field.readOnly)
            {
                if (writtenAt(kind, field.id, field.versioned))
                {
                    static if (is(typeof(T.tupleof[index]) == long))
                        output[count++] = signed64(entity.tupleof[index]);
                    else
                    {
                        const encoded = encodeCell(entity.tupleof[index], output[count++]);
                        if (encoded.code != Status.ok)
                            return encoded;
                    }
                }
            }
        }
        if (kind != Mutation.replace)
            return Error.init;
        static if (is(Mapping.Key == long))
            output[count++] = signed64(entity.tupleof[Mapping.id]);
        else
        {
            const key = encodeCell(entity.tupleof[Mapping.id], output[count++]);
            if (key.code != Status.ok)
                return key;
        }
        static if (Mapping.revision != absent)
            return encodeRevision(entity.tupleof[Mapping.revision], output[count++]);
        else
            return Error.init;
    }

    /// Delete the identifier if present.
    override Error deleteById(ID id, ref Context context) nothrow @nogc
    {
        SqlValue key;
        const checked = bindKey(id, key);
        if (checked.code != Status.ok)
            return checked;
        return execute(pool, sql.delete_, key, context);
    }

    /// Determine whether a row exists without materializing an entity.
    override Presence existsById(ID id, ref Context context) nothrow @nogc
    {
        SqlValue key;
        const checked = bindKey(id, key);
        if (checked.code != Status.ok)
            return Presence(false, checked);
        return exists(pool, sql.exists, key, context);
    }

    private Error bindKey(ID id, out SqlValue value) nothrow @nogc
    {
        static if (is(ID == long))
        {
            value = signed64(id);
            return Error.init;
        }
        else
            return encodeCell(id, value);
    }

    private Outcome read(string sql, scope Values params, ref scope Arena arena, ref Context context) nothrow @nogc
    {
        Outcome result;
        result.error = one(pool, sql, params, arena, context, (ref Row row) @safe nothrow @nogc {
            return readEntity(result.value, row, arena);
        });
        if (!result.ok())
            result.value = T.init;
        return result;
    }

    private Error readEntity(ref T entity, ref Row row, ref scope Arena arena) nothrow @nogc
    {
        if (row.columns() != Mapping.fields.length)
            return Error(Status.invalidArgument, "SQL row has the wrong column count");
        static foreach (index; 0 .. Mapping.fields.length)
        {
            {
                static if (is(typeof(T.tupleof[index]) == long))
                    const decoded = readInt64(entity.tupleof[index], row, cast(uint) index, arena);
                else
                    const decoded = readField(entity.tupleof[index], row, cast(uint) index, arena);
                if (decoded.code != Status.ok)
                    return decoded;
            }
        }
        return Error.init;
    }

    /// Run the Query UDA on Args against explicitly named projection columns.
    Result!Projection queryOne(Projection, Args)(scope const ref Args arguments,
            ref scope RequestArena arena, ref Context context) nothrow @nogc
    {
        alias Plan = NamedQuery!(Projection, Args);
        SqlValue[Plan.order.length] parameters;
        Result!Projection projected;
        projected.error = namedParameters!(Args, Plan)(arguments, parameters[]);
        if (!projected.ok())
            return projected;
        projected.error = one(pool, Plan.sql, parameters[], arena, context, (ref Row row) @safe nothrow @nogc {
            return decodeRow(projected.value, row, arena);
        });
        if (!projected.ok())
            projected.value = Projection.init;
        return projected;
    }
}
