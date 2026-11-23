/// Stable single-statement SQL generation and parameter order.
module flint.engine.data.internal.sqlgen;

import flint.engine.data.internal.schema : Field, absent;

@safe:

package(flint.engine.data) struct Statements
{
    string schema;
    string find;
    string create;
    string explicitInsert;
    string update;
    string delete_;
    string exists;
}

package(flint.engine.data) string quoted(string identifier) pure
{
    return "\"" ~ identifier ~ "\"";
}

package(flint.engine.data) string spelling(size_t number) pure
{
    char[20] digits;
    size_t start = digits.length;
    do
    {
        digits[--start] = cast(char)('0' + number % 10);
        number /= 10;
    }
    while (number != 0);
    return digits[start .. $].idup;
}

package(flint.engine.data) string placeholder(size_t ordinal) pure
{
    return "$" ~ spelling(ordinal);
}

package(flint.engine.data) string projection(scope const Field[] fields, string origin = "") pure
{
    string columns;
    foreach (index, ref const field; fields)
    {
        if (index != 0)
            columns ~= ", ";
        if (origin.length != 0)
            columns ~= quoted(origin) ~ ".";
        columns ~= quoted(field.name);
    }
    return columns;
}

private string create(string table, string returning, scope const Field[] fields, bool includeId) pure
{
    string names;
    string values;
    size_t ordinal;
    foreach (ref const field; fields)
    {
        if (field.readOnly || (field.id && !includeId))
            continue;
        if (ordinal != 0)
        {
            names ~= ", ";
            values ~= ", ";
        }
        names ~= quoted(field.name);
        values ~= placeholder(++ordinal);
    }
    const prefix = "INSERT INTO " ~ table;
    if (ordinal == 0)
        return prefix ~ " DEFAULT VALUES" ~ returning;
    return prefix ~ " (" ~ names ~ ") VALUES (" ~ values ~ ")" ~ returning;
}

private string update(string table, string returning, scope const Field[] fields, size_t id, size_t revision) pure
{
    size_t ordinal;
    string assignments;
    foreach (ref const field; fields)
    {
        if (field.readOnly || field.id || field.versioned)
            continue;
        if (ordinal != 0)
            assignments ~= ", ";
        assignments ~= quoted(field.name) ~ " = " ~ placeholder(++ordinal);
    }

    const key = quoted(fields[id].name);
    if (revision == absent && ordinal == 0)
        return "UPDATE " ~ table ~ " SET " ~ key ~ " = " ~ key ~ " WHERE " ~ key ~ " = $1" ~ returning;
    if (revision == absent)
        return "UPDATE " ~ table ~ " SET " ~ assignments ~ " WHERE " ~ key ~ " = " ~ placeholder(ordinal + 1)
            ~ returning;

    const column = quoted(fields[revision].name);
    if (ordinal != 0)
        assignments ~= ", ";
    assignments ~= column ~ " = " ~ column ~ " + 1";
    return "UPDATE " ~ table ~ " SET " ~ assignments ~ " WHERE " ~ key ~ " = " ~ placeholder(
            ordinal + 1) ~ " AND " ~ column ~ " = " ~ placeholder(ordinal + 2) ~ returning;
}

package(flint.engine.data) Statements generate(string name, scope const Field[] fields, size_t id, size_t revision) pure
{
    const table = quoted(name);
    enum origin = "_flint_table";
    const read = "SELECT " ~ projection(fields, origin) ~ " FROM " ~ table ~ " AS " ~ quoted(origin);
    const key = quoted(fields[id].name) ~ " = $1";
    const returning = " RETURNING " ~ projection(fields);
    return Statements(read ~ " WHERE 1 = 0", read ~ " WHERE " ~ key ~ " LIMIT 2", create(table,
            returning, fields, false), create(table, returning, fields, true), update(table,
            returning, fields, id, revision), "DELETE FROM " ~ table ~ " WHERE " ~ key,
            "SELECT 1 FROM " ~ table ~ " WHERE " ~ key ~ " LIMIT 1");
}
