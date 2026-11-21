// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.data;
import flint.arena : Error, RequestArena, Result;
import flint.conc : Context;
import flint.sql : Pool;

@safe:
struct Table
{
    string name;
}

struct Id
{
}

struct Column
{
    string name;
}

struct Query
{
    string sql;
}

struct Version
{
}

struct ReadOnly
{
}

struct PageRequest
{
    uint limit = 100;
    ulong offset;
}

struct Page(T)
{
    T[] items;
    bool hasMore;
}

interface CrudRepository(T, ID)
{
    Result!T findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!T save(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error deleteById(ID id, ref Context context) nothrow @nogc;
    Result!bool existsById(ID id, ref Context context) nothrow @nogc;
}

final class SqlRepository(T, ID) : CrudRepository!(T, ID)
{
    this(ref Pool pool);
    override Result!T findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    override Result!T save(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    override Error deleteById(ID id, ref Context context) nothrow @nogc;
    override Result!bool existsById(ID id, ref Context context) nothrow @nogc;
}

Error mapRow(T)(ref T entity, ref scope RequestArena arena, scope const(char)[] column, scope const(ubyte)[] value) nothrow @nogc;
