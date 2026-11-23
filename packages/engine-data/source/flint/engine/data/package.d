/// Compile-time entity repositories and caller-owned SQL row codecs.
module flint.engine.data;

import flint.arena : Error, RequestArena;
import flint.engine.data.internal.mapper : decodeColumn;
public import flint.engine.data.internal.repository_type : CrudRepository, SqlRepository;
public import flint.engine.data.types : Column, Id, Nullable, Page, PageRequest, Query, ReadOnly, Table, Version;

@safe:

private alias Bytes = const(ubyte)[];

/// Map one non-null, textual or binary cell using its declared column name.
Error mapRow(T)(ref T entity, ref scope RequestArena arena, scope const(char)[] column, scope Bytes value) nothrow @nogc
{
    return decodeColumn(entity, arena, column, value);
}
