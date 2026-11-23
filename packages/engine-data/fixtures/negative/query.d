module query_negative;

import flint.arena : RequestArena, Result;
import flint.conc : Context;
import flint.engine.data : Column, Id, Query, SqlRepository, Table;

@safe:

@Table("records")
private struct Record
{
    @Id
    long id;
}

private struct Projection
{
    long value;
}

version (FlintDataUnknownParameter)
{
    @Query("SELECT :unknown AS value")
    private struct Args
    {
        long key;
    }
}
else version (FlintDataUnusedParameter)
{
    @Query("SELECT ':key' AS value /* :key */")
    private struct Args
    {
        long key;
    }
}
else version (FlintDataDuplicateParameter)
{
    @Query("SELECT :key AS value")
    private struct Args
    {
        @Column("key")
        long first;
        @Column("key")
        bool duplicate;
    }
}
else version (FlintDataBoundMarker)
{
    @Query("SELECT :key + $1 AS value")
    private struct Args
    {
        long key;
    }
}
else version (FlintDataMultipleStatements)
{
    @Query("SELECT :key AS value; SELECT 2 AS value")
    private struct Args
    {
        long key;
    }
}
else version (FlintDataUnterminatedLiteral)
{
    @Query("SELECT ':key AS value")
    private struct Args
    {
        long key;
    }
}

private alias Repository = SqlRepository!(Record, long);

/// Instantiate a generated named query with an invalid binding declaration.
Result!Projection rejectQuery(Repository repository, ref scope RequestArena arena, ref Context context)
{
    const params = Args.init;
    return repository.queryOne!Projection(params, arena, context);
}
