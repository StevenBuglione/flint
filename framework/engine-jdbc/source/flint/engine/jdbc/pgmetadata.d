// Ported from pgjdbc REL42.7.14: pgjdbc/src/main/java/org/postgresql/jdbc/PgDatabaseMetaData.java
// Also ported: pgjdbc/src/main/java/org/postgresql/jdbc/TypeInfoCache.java (the built-in type table, getPrecision,
// getScale and getDisplaySize); from PgDatabaseMetaData: getTables, getColumns and tableTypeClauses.
// Copyright (c) 2004, PostgreSQL Global Development Group
// Copyright (c) 2005, PostgreSQL Global Development Group (TypeInfoCache)
// Licensed under the BSD 2-Clause License (SPDX-License-Identifier: BSD-2-Clause); see the LICENSE file in pgjdbc's
// root and Flint's NOTICE.
// Modified by the Flint authors.
/*
 * Changes: D. The queries are built as pgjdbc builds them for a server of version 12 or later (Flint's PostgreSQL
 * support) with hideUnprivilegedObjects off, so the server receives the same statement text and parameters. The
 * getColumns row post-processing returns plain values for flint.engine.jdbc to put in its result set.
 * TypeInfoCache's server lookups for types outside its built-in table are not ported: such a column reports
 * Types.OTHER (or the STRUCT, DISTINCT and VARCHAR of composite, domain and enum types, as pgjdbc does) and no
 * type name.
 */
/// pgjdbc's DatabaseMetaData.getTables and getColumns for PostgreSQL: their catalog queries and column rows.
module flint.engine.jdbc.pgmetadata;

import flint.java.sql : Types;

@safe:

/// pgjdbc's getTables text up to its filters, in pgjdbc's pieces: the server receives exactly their concatenation.
private immutable string[] tablesSelectPieces = [
    "SELECT current_database() AS \"TABLE_CAT\", n.nspname AS \"TABLE_SCHEM\", ",
    "c.relname AS \"TABLE_NAME\", ", " CASE n.nspname ~ '^pg_' OR n.nspname = 'information_schema' ",
    " WHEN true THEN CASE ",
    " WHEN n.nspname = 'pg_catalog' OR n.nspname = 'information_schema' THEN CASE c.relkind ",
    "  WHEN 'r' THEN 'SYSTEM TABLE' ", "  WHEN 'v' THEN 'SYSTEM VIEW' ",
    "  WHEN 'i' THEN 'SYSTEM INDEX' ", "  ELSE NULL ", "  END ",
    " WHEN n.nspname = 'pg_toast' THEN CASE c.relkind ", "  WHEN 'r' THEN 'SYSTEM TOAST TABLE' ",
    "  WHEN 'i' THEN 'SYSTEM TOAST INDEX' ", "  ELSE NULL ", "  END ", " ELSE CASE c.relkind ",
    "  WHEN 'r' THEN 'TEMPORARY TABLE' ", "  WHEN 'p' THEN 'TEMPORARY TABLE' ",
    "  WHEN 'i' THEN 'TEMPORARY INDEX' ", "  WHEN 'S' THEN 'TEMPORARY SEQUENCE' ",
    "  WHEN 'v' THEN 'TEMPORARY VIEW' ", "  ELSE NULL ", "  END ", " END ",
    " WHEN false THEN CASE c.relkind ", " WHEN 'r' THEN 'TABLE' ",
    " WHEN 'p' THEN 'PARTITIONED TABLE' ", " WHEN 'i' THEN 'INDEX' ",
    " WHEN 'P' then 'PARTITIONED INDEX' ", " WHEN 'S' THEN 'SEQUENCE' ", " WHEN 'v' THEN 'VIEW' ",
    " WHEN 'c' THEN 'TYPE' ", " WHEN 'f' THEN 'FOREIGN TABLE' ",
    " WHEN 'm' THEN 'MATERIALIZED VIEW' ", " ELSE NULL ",
    " END ", " ELSE NULL ", " END ", " AS \"TABLE_TYPE\", d.description AS \"REMARKS\", ",
    " '' as \"TYPE_CAT\", '' as \"TYPE_SCHEM\", '' as \"TYPE_NAME\", ",
    "'' AS \"SELF_REFERENCING_COL_NAME\", '' AS \"REF_GENERATION\" ",
    " FROM pg_catalog.pg_namespace n, pg_catalog.pg_class c ",
    " LEFT JOIN pg_catalog.pg_description d ON (c.oid = d.objoid AND d.objsubid = 0  and d.classoid = ",
    "'pg_class'::regclass) ", " WHERE c.relnamespace = n.oid ",
];

private enum string tablesSelect = joined(tablesSelectPieces);

private string joined(const(string)[] pieces) pure nothrow
{
    string text;
    foreach (piece; pieces)
        text ~= piece;
    return text;
}

/++
pgjdbc's getTables statement (catalog matched by the caller) and its parameters in order: `schemaPattern` and
`tableNamePattern` when not null, then a clause per known table type in `types`.
+/
package(flint.engine.jdbc) string tablesSql(string schemaPattern, string tableNamePattern,
        const(string)[] types, ref string[] args)
{
    string select = tablesSelect;
    if (schemaPattern !is null)
    {
        select ~= " AND n.nspname LIKE ?";
        args ~= schemaPattern;
    }
    const orderby = " ORDER BY \"TABLE_TYPE\",\"TABLE_SCHEM\",\"TABLE_NAME\" ";
    if (tableNamePattern !is null)
    {
        select ~= " AND c.relname LIKE ?";
        args ~= tableNamePattern;
    }
    if (types !is null)
    {
        select ~= " AND (false ";
        foreach (type; types)
            if (const clause = tableTypeClause(type))
                select ~= " OR ( " ~ clause ~ " ) ";
        select ~= ") ";
    }
    return select ~ orderby;
}

/// pgjdbc's tableTypeClauses, schema form: each JDBC table type and the condition selecting its relations.
private immutable string[2][19] tableTypeClauses = [
    ["TABLE", "c.relkind = 'r' AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'"],
    [
        "PARTITIONED TABLE",
        "c.relkind = 'p' AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'"
    ], [
        "VIEW", "c.relkind = 'v' AND n.nspname <> 'pg_catalog' AND n.nspname <> 'information_schema'"
    ], ["INDEX", "c.relkind = 'i' AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'"],
    [
        "PARTITIONED INDEX",
        "c.relkind = 'I' AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'"
    ], ["SEQUENCE", "c.relkind = 'S'"],
    ["TYPE", "c.relkind = 'c' AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'"],
    [
        "SYSTEM TABLE",
        "c.relkind = 'r' AND (n.nspname = 'pg_catalog' OR n.nspname = 'information_schema')"
    ], ["SYSTEM TOAST TABLE",
        "c.relkind = 'r' AND n.nspname = 'pg_toast'"],
    ["SYSTEM TOAST INDEX", "c.relkind = 'i' AND n.nspname = 'pg_toast'"],
    [
        "SYSTEM VIEW",
        "c.relkind = 'v' AND (n.nspname = 'pg_catalog' OR n.nspname = 'information_schema') "
    ],
    [
        "SYSTEM INDEX",
        "c.relkind = 'i' AND (n.nspname = 'pg_catalog' OR n.nspname = 'information_schema') "
    ], ["TEMPORARY TABLE", "c.relkind IN ('r','p') AND n.nspname ~ '^pg_temp_' "],
    ["TEMPORARY INDEX", "c.relkind = 'i' AND n.nspname ~ '^pg_temp_' "],
    ["TEMPORARY VIEW", "c.relkind = 'v' AND n.nspname ~ '^pg_temp_' "],
    ["TEMPORARY SEQUENCE", "c.relkind = 'S' AND n.nspname ~ '^pg_temp_' "],
    ["FOREIGN TABLE", "c.relkind = 'f'"], ["MATERIALIZED VIEW", "c.relkind = 'm'"], ["", ""]
];

/// The condition selecting relations of a JDBC table type, or null for a type pgjdbc does not know.
private string tableTypeClause(string type) pure nothrow @nogc
{
    foreach (ref entry; tableTypeClauses)
        if (entry[0].length && entry[0] == type)
            return entry[1];
    return null;
}

/// pgjdbc's getColumns statement for a server of version 12 or later, and its parameters in order.
package(flint.engine.jdbc) string columnsSql(string schemaPattern, string tableNamePattern,
        string columnNamePattern, ref string[] args)
{
    string sql = "SELECT * FROM (";
    sql ~= "SELECT current_database() AS current_database, n.nspname,c.relname,a.attname,a.atttypid,a.attnotnull "
        ~ " OR (t.typtype = 'd' AND t.typnotnull) AS attnotnull,a.atttypmod,a.attlen,t.typtypmod,";
    sql ~= "row_number() OVER (PARTITION BY a.attrelid ORDER BY a.attnum) AS attnum, ";
    sql ~= "nullif(a.attidentity, '') as attidentity,";
    sql ~= "nullif(a.attgenerated, '') as attgenerated,";
    sql ~= "pg_catalog.pg_get_expr(def.adbin, def.adrelid) AS adsrc,dsc.description,t.typbasetype,t.typtype "
        ~ " FROM pg_catalog.pg_namespace n " ~ " JOIN pg_catalog.pg_class c ON (c.relnamespace = n.oid) "
        ~ " JOIN pg_catalog.pg_attribute a ON (a.attrelid=c.oid) "
        ~ " JOIN pg_catalog.pg_type t ON (a.atttypid = t.oid) "
        ~ " LEFT JOIN pg_catalog.pg_attrdef def ON (a.attrelid=def.adrelid AND a.attnum = def.adnum) "
        ~ " LEFT JOIN pg_catalog.pg_description dsc ON (c.oid=dsc.objoid AND a.attnum = dsc.objsubid) "
        ~ " LEFT JOIN pg_catalog.pg_class dc ON (dc.oid=dsc.classoid AND dc.relname='pg_class') "
        ~ " LEFT JOIN pg_catalog.pg_namespace dn ON (dc.relnamespace=dn.oid AND dn.nspname='pg_catalog') "
        ~ " WHERE c.relkind in ('r','p','v','f','m') and a.attnum > 0 AND NOT a.attisdropped ";
    if (schemaPattern !is null)
    {
        sql ~= " AND n.nspname LIKE ?";
        args ~= schemaPattern;
    }
    if (tableNamePattern !is null)
    {
        sql ~= " AND c.relname LIKE ?";
        args ~= tableNamePattern;
    }
    sql ~= ") c WHERE true ";
    if (columnNamePattern !is null)
    {
        sql ~= " AND attname LIKE ?";
        args ~= columnNamePattern;
    }
    return sql ~ " ORDER BY nspname,c.relname,attnum ";
}

/// JDBC's columnNoNulls and columnNullable.
private enum int columnNoNulls = 0, columnNullable = 1;

/// getColumns' labels, in order: JDBC 4's 24 columns.
package(flint.engine.jdbc) immutable string[24] columnLabels = [
    "TABLE_CAT", "TABLE_SCHEM", "TABLE_NAME", "COLUMN_NAME", "DATA_TYPE", "TYPE_NAME",
    "COLUMN_SIZE", "BUFFER_LENGTH", "DECIMAL_DIGITS",
    "NUM_PREC_RADIX", "NULLABLE",
    "REMARKS", "COLUMN_DEF", "SQL_DATA_TYPE", "SQL_DATETIME_SUB", "CHAR_OCTET_LENGTH",
    "ORDINAL_POSITION", "IS_NULLABLE", "SCOPE_CATALOG", "SCOPE_SCHEMA", "SCOPE_TABLE",
    "SOURCE_DATA_TYPE", "IS_AUTOINCREMENT", "IS_GENERATEDCOLUMN"
];

/// One row of the getColumns query, as the columns pgjdbc reads from it.
package(flint.engine.jdbc) struct CatalogColumn
{
    string catalog; /// the connection's current catalog
    string nspname, relname, attname, typtype, adsrc, attidentity, attgenerated, description;
    long atttypid, typbasetype;
    int atttypmod, typtypmod, attnum;
    bool attnotnull;
}

/// A getColumns cell: SQL NULL, an integer, or text.
package(flint.engine.jdbc) struct MetaValue
{
    enum Kind
    {
        null_,
        integer,
        text
    }

    Kind kind; ///
    long integer; ///
    string text; ///

    static MetaValue of(long value) pure nothrow @nogc ///
    {
        return MetaValue(Kind.integer, value, null);
    }

    static MetaValue of(string value) pure nothrow @nogc ///
    {
        return value is null ? MetaValue.init : MetaValue(Kind.text, 0, value);
    }
}

/// pgjdbc's getColumns row for `raw`, in `columnLabels` order.
package(flint.engine.jdbc) MetaValue[24] columnRow(const ref CatalogColumn raw) pure nothrow
{
    MetaValue[24] tuple;
    const typeOid = cast(int) raw.atttypid;
    const typeMod = raw.atttypmod;
    tuple[0] = MetaValue.of(raw.catalog);
    tuple[1] = MetaValue.of(raw.nspname);
    tuple[2] = MetaValue.of(raw.relname);
    tuple[3] = MetaValue.of(raw.attname);
    const sqlType = columnSqlType(raw.typtype, typeOid);
    tuple[4] = MetaValue.of(sqlType);
    const pgType = pgTypeOf(typeOid);
    tuple[5] = MetaValue.of(serialName(raw.adsrc, pgType));
    tuple[7] = MetaValue.init; // Buffer length
    const baseTypeOid = cast(int) raw.typbasetype;
    const size = sizeOf(raw, sqlType, baseTypeOid);
    const decimalDigits = size.decimalDigits;
    tuple[6] = MetaValue.of(size.columnSize);
    // Give null for an unset scale on Decimal and Numeric columns
    if (!((sqlType == Types.NUMERIC || sqlType == Types.DECIMAL) && typeMod == -1))
        tuple[8] = MetaValue.of(decimalDigits);
    // Everything is base 10 unless we override later.
    tuple[9] = MetaValue.of(pgType == "bit" || pgType == "varbit" ? 2 : 10);
    tuple[10] = MetaValue.of(raw.attnotnull ? columnNoNulls : columnNullable);
    tuple[11] = MetaValue.of(raw.description);
    tuple[12] = MetaValue.of(raw.adsrc);
    // CHAR_OCTET_LENGTH applies to character and binary types only; it equals COLUMN_SIZE there.
    if (isCharacterOrBinary(sqlType))
        tuple[15] = tuple[6];
    tuple[16] = MetaValue.of(raw.attnum);
    tuple[17] = MetaValue.of(raw.attnotnull ? "NO" : "YES");
    if (baseTypeOid != 0)
        tuple[21] = MetaValue.of(sqlTypeOf(baseTypeOid));
    const autoIncrement = (raw.adsrc !is null && contains(raw.adsrc, "nextval(")) || raw.attidentity !is null;
    tuple[22] = MetaValue.of(autoIncrement ? "YES" : "NO");
    tuple[23] = MetaValue.of(raw.attgenerated !is null ? "YES" : "NO");
    return tuple;
}

/// A column's `Types` code: STRUCT, DISTINCT and VARCHAR for composite, domain and enum types, else its type's.
private int columnSqlType(string typtype, int typeOid) pure nothrow @nogc
{
    if (typtype == "c")
        return Types.STRUCT;
    if (typtype == "d")
        return Types.DISTINCT;
    if (typtype == "e")
        return Types.VARCHAR;
    return sqlTypeOf(typeOid);
}

/// A column's DECIMAL_DIGITS and COLUMN_SIZE.
private struct Size
{
    int decimalDigits;
    int columnSize;
}

/// A column's decimal digits and size, as pgjdbc's getColumns works them out.
private Size sizeOf(const ref CatalogColumn raw, int sqlType, int baseTypeOid) pure nothrow @nogc
{
    if (sqlType == Types.DISTINCT)
        return domainSize(raw, baseTypeOid);
    const typeOid = cast(int) raw.atttypid;
    auto size = Size(scaleOf(typeOid, raw.atttypmod), precisionOf(typeOid, raw.atttypmod));
    if (sqlType != Types.NUMERIC && size.columnSize == 0)
        size.columnSize = displaySizeOf(typeOid, raw.atttypmod);
    return size;
}

/// The type name pgjdbc reports for a column whose default draws from a sequence: serial, bigserial, smallserial.
private string serialName(string defval, string pgType) pure nothrow @nogc
{
    if (defval is null || !contains(defval, "nextval("))
        return pgType;
    switch (pgType)
    {
    case "int4":
        return "serial";
    case "int8":
        return "bigserial";
    case "int2":
        return "smallserial";
    default:
        return pgType;
    }
}

/// A domain's precision and scale: from its base type, or its own typmod (pgjdbc's DISTINCT branch).
private Size domainSize(const ref CatalogColumn raw, int baseTypeOid) pure nothrow @nogc
{
    const decimalDigits = scaleOf(baseTypeOid, raw.atttypmod);
    if (raw.typtypmod == -1)
        return Size(decimalDigits, precisionOf(baseTypeOid, raw.atttypmod));
    if (baseTypeOid == Oid.numeric)
        return Size(scaleOf(baseTypeOid, raw.typtypmod), precisionOf(baseTypeOid, raw.typtypmod));
    return Size(decimalDigits, raw.typtypmod);
}

private bool isCharacterOrBinary(int sqlType) pure nothrow @nogc
{
    switch (sqlType)
    {
    case Types.CHAR, Types.VARCHAR, Types.LONGVARCHAR, Types.NCHAR, Types.NVARCHAR,
            Types.LONGNVARCHAR, Types.CLOB, Types.NCLOB, Types.BINARY, Types.VARBINARY,
            Types.LONGVARBINARY, Types.BLOB:
            return true;
    default:
        return false;
    }
}

private bool contains(string text, string part) pure nothrow @nogc
{
    if (part.length > text.length)
        return false;
    foreach (i; 0 .. text.length - part.length + 1)
        if (text[i .. i + part.length] == part)
            return true;
    return false;
}

// ---------------------------------------------------------------------------------------------------------------
// TypeInfoCache: the built-in types

/// PostgreSQL's type OIDs that TypeInfoCache's table and functions name (org.postgresql.core.Oid).
private enum Oid : int
{
    int2 = 21,
    int4 = 23,
    oid = 26,
    int8 = 20,
    money = 790,
    numeric = 1700,
    float4 = 700,
    float8 = 701,
    char_ = 18,
    bpchar = 1042,
    varchar = 1043,
    varbit = 1562,
    text = 25,
    name = 19,
    bytea = 17,
    bool_ = 16,
    bit = 1560,
    date = 1082,
    time = 1083,
    timetz = 1266,
    timestamp = 1114,
    timestamptz = 1184,
    interval = 1186,
    refCursor = 1790,
    json = 114,
    jsonb = 3802,
    point = 600,
    box = 603
}

/// TypeInfoCache's types table: name, OID, `Types` code and array OID.
private struct BuiltIn
{
    string name;
    int oid;
    int sqlType;
    int arrayOid;
}

private immutable BuiltIn[27] builtIns = [
    BuiltIn("int2", Oid.int2, Types.SMALLINT, 1005), BuiltIn("int4", Oid.int4, Types.INTEGER,
            1007), BuiltIn("oid", Oid.oid, Types.BIGINT, 1028),
    BuiltIn("int8", Oid.int8, Types.BIGINT, 1016), BuiltIn("money", Oid.money, Types.DOUBLE, 791),
    BuiltIn("numeric", Oid.numeric, Types.NUMERIC, 1231),
    BuiltIn("float4", Oid.float4, Types.REAL, 1021), BuiltIn("float8", Oid.float8, Types.DOUBLE,
            1022), BuiltIn("char", Oid.char_, Types.CHAR, 1002),
    BuiltIn("bpchar", Oid.bpchar, Types.CHAR, 1014),
    BuiltIn("varchar", Oid.varchar, Types.VARCHAR, 1015),
    BuiltIn("varbit", Oid.varbit, Types.OTHER, 1563), BuiltIn("text", Oid.text, Types.VARCHAR,
            1009), BuiltIn("name", Oid.name, Types.VARCHAR, 1003),
    BuiltIn("bytea", Oid.bytea, Types.BINARY, 1001), BuiltIn("bool", Oid.bool_, Types.BIT, 1000),
    BuiltIn("bit", Oid.bit, Types.BIT, 1561), BuiltIn("date", Oid.date, Types.DATE, 1182),
    BuiltIn("time", Oid.time, Types.TIME, 1183), BuiltIn("timetz", Oid.timetz, Types.TIME, 1270),
    BuiltIn("timestamp", Oid.timestamp, Types.TIMESTAMP, 1115),
    BuiltIn("timestamptz", Oid.timestamptz, Types.TIMESTAMP, 1185),
    BuiltIn("refcursor", Oid.refCursor, Types.REF_CURSOR, 2201),
    BuiltIn("json", Oid.json, Types.OTHER, 199), BuiltIn("jsonb", Oid.jsonb, Types.OTHER, 3807),
    BuiltIn("point", Oid.point, Types.OTHER, 1017), BuiltIn("box", Oid.box, Types.OTHER, 1020)
];

/// The `Types` code of a type: its table entry's, ARRAY for an array of one, OTHER for any other type.
private int sqlTypeOf(int oid) pure nothrow @nogc
{
    foreach (ref type; builtIns)
    {
        if (type.oid == oid)
            return type.sqlType;
        if (type.arrayOid == oid)
            return Types.ARRAY;
    }
    return Types.OTHER;
}

/// The type's PostgreSQL name: its table entry's, `_name` for an array of one; null for any other type.
private string pgTypeOf(int oid) pure nothrow
{
    foreach (ref type; builtIns)
    {
        if (type.oid == oid)
            return type.name;
        if (type.arrayOid == oid)
            return "_" ~ type.name;
    }
    return null;
}

/// TypeInfoCache.convertArrayToBaseOid: an array type's element type.
private int baseOf(int oid) pure nothrow @nogc
{
    foreach (ref type; builtIns)
        if (type.arrayOid == oid)
            return type.oid;
    return oid;
}

private enum unknownLength = int.max;

/// TypeInfoCache.getPrecision.
private int precisionOf(int oid, int typmod) pure nothrow @nogc
{
    switch (baseOf(oid))
    {
    case Oid.int2:
        return 5;
    case Oid.oid, Oid.int4:
        return 10;
    case Oid.int8:
        return 19;
    case Oid.float4:
        return 8;
    case Oid.float8:
        return 17;
    case Oid.numeric:
        return typmod == -1 ? 0 : ((typmod - 4) & 0xFFFF0000) >> 16;
    case Oid.char_, Oid.bool_:
        return 1;
    case Oid.bpchar, Oid.varchar:
        return typmod == -1 ? unknownLength : typmod - 4;
    case Oid.date, Oid.time, Oid.timetz, Oid.interval, Oid.timestamp, Oid.timestamptz:
        return displaySizeOf(oid, typmod);
    case Oid.bit:
        return typmod;
    case Oid.varbit:
        return typmod == -1 ? unknownLength : typmod;
    default:
        return unknownLength;
    }
}

/// TypeInfoCache.getScale.
private int scaleOf(int oid, int typmod) pure nothrow @nogc
{
    switch (baseOf(oid))
    {
    case Oid.float4:
        return 8;
    case Oid.float8:
        return 17;
    case Oid.numeric:
        return typmod == -1 ? 0 : (typmod - 4) & 0xFFFF;
    case Oid.time, Oid.timetz, Oid.timestamp, Oid.timestamptz:
        return typmod == -1 ? 6 : typmod;
    case Oid.interval:
        return typmod == -1 ? 6 : typmod & 0xFFFF;
    default:
        return 0;
    }
}

/// TypeInfoCache.getDisplaySize.
private int displaySizeOf(int oid, int typmod) pure nothrow @nogc
{
    const base = baseOf(oid);
    switch (base)
    {
    case Oid.int2:
        return 6; // -32768 to +32767
    case Oid.int4:
        return 11; // -2147483648 to +2147483647
    case Oid.oid:
        return 10; // 0 to 4294967295
    case Oid.int8:
        return 20; // -9223372036854775808 to +9223372036854775807
    case Oid.float4:
        return 15; // sign + 9 digits + decimal point + e + sign + 2 digits
    case Oid.float8:
        return 25; // sign + 18 digits + decimal point + e + sign + 3 digits
    case Oid.char_, Oid.bool_:
        return 1;
    case Oid.date:
        return 13; // "4713-01-01 BC" to "01/01/4713 BC" - "31/12/32767"
    case Oid.time, Oid.timetz, Oid.timestamp, Oid.timestamptz:
        return timeDisplaySize(base, typmod);
    case Oid.interval:
        return 49;
    case Oid.varchar, Oid.bpchar:
        return typmod == -1 ? unknownLength : typmod - 4;
    case Oid.numeric:
        return numericDisplaySize(typmod);
    case Oid.bit:
        return typmod;
    case Oid.varbit:
        return typmod == -1 ? unknownLength : typmod;
    default:
        return unknownLength;
    }
}

/// A numeric's display size: sign, digits, and the decimal point when it has a scale.
private int numericDisplaySize(int typmod) pure nothrow @nogc
{
    if (typmod == -1)
        return 131_089; // SELECT LENGTH(pow(10::numeric,131071)); 131071 = 2^17-1
    const precision = ((typmod - 4) >> 16) & 0xffff;
    const scale = (typmod - 4) & 0xffff;
    return 1 + precision + (scale != 0 ? 1 : 0);
}

/// The time types' display size: the digits of the seconds' fraction, plus the time, date and zone they carry.
private int timeDisplaySize(int oid, int typmod) pure nothrow @nogc
{
    // Calculate the number of decimal digits + the decimal point.
    const secondSize = typmod == -1 ? 6 + 1 : typmod == 0 ? 0 : typmod == 1 ? 2 + 1 : typmod + 1;
    // time = '00:00:00' = 8; date = '5874897-12-31' = 13; zone = '+11:30' = 6
    switch (oid)
    {
    case Oid.time:
        return 8 + secondSize;
    case Oid.timetz:
        return 8 + secondSize + 6;
    case Oid.timestamp:
        return 13 + 1 + 8 + secondSize;
    default:
        return 13 + 1 + 8 + secondSize + 6;
    }
}

@("getTables and getColumns send pgjdbc 42.7.14's statements, character for character (the Java reference's log)")
unittest
{
    // As the Java reference's PostgreSQL log records them for SimpleJdbcInsert's table lookup, markers as JDBC's.
    static immutable string[] javaTablesParts = [
        "SELECT current_database() AS \"TABLE_CAT\", n.nspname AS \"TABLE_SCHEM\", ",
        "c.relname AS \"TABLE_NAME\",  CASE n.nspname ~ '^pg_' OR n.nspname = 'in",
        "formation_schema'  WHEN true THEN CASE  WHEN n.nspname = 'pg_catalog' ",
        "OR n.nspname = 'information_schema' THEN CASE c.relkind   WHEN 'r' THE",
        "N 'SYSTEM TABLE'   WHEN 'v' THEN 'SYSTEM VIEW'   WHEN 'i' THEN 'SYSTEM",
        " INDEX'   ELSE NULL   END  WHEN n.nspname = 'pg_toast' THEN CASE c.rel",
        "kind   WHEN 'r' THEN 'SYSTEM TOAST TABLE'   WHEN 'i' THEN 'SYSTEM TOAS",
        "T INDEX'   ELSE NULL   END  ELSE CASE c.relkind   WHEN 'r' THEN 'TEMPO",
        "RARY TABLE'   WHEN 'p' THEN 'TEMPORARY TABLE'   WHEN 'i' THEN 'TEMPORA",
        "RY INDEX'   WHEN 'S' THEN 'TEMPORARY SEQUENCE'   WHEN 'v' THEN 'TEMPOR",
        "ARY VIEW'   ELSE NULL   END  END  WHEN false THEN CASE c.relkind  WHEN",
        " 'r' THEN 'TABLE'  WHEN 'p' THEN 'PARTITIONED TABLE'  WHEN 'i' THEN 'I",
        "NDEX'  WHEN 'P' then 'PARTITIONED INDEX'  WHEN 'S' THEN 'SEQUENCE'  WH",
        "EN 'v' THEN 'VIEW'  WHEN 'c' THEN 'TYPE'  WHEN 'f' THEN 'FOREIGN TABLE",
        "'  WHEN 'm' THEN 'MATERIALIZED VIEW'  ELSE NULL  END  ELSE NULL  END  ",
        "AS \"TABLE_TYPE\", d.description AS \"REMARKS\",  '' as \"TYPE_CAT\", '' as ",
        "\"TYPE_SCHEM\", '' as \"TYPE_NAME\", '' AS \"SELF_REFERENCING_COL_NAME\", ''",
        " AS \"REF_GENERATION\"  FROM pg_catalog.pg_namespace n, pg_catalog.pg_cl",
        "ass c  LEFT JOIN pg_catalog.pg_description d ON (c.oid = d.objoid AND ",
        "d.objsubid = 0  and d.classoid = 'pg_class'::regclass)  WHERE c.relnam",
        "espace = n.oid  AND c.relname LIKE ? ORDER BY \"TABLE_TYPE\",\"TABLE_SCHE",
        "M\",\"TABLE_NAME\" "
    ];
    static immutable string[] javaColumnsParts = [
        "SELECT * FROM (SELECT current_database() AS current_database, n.nspnam",
        "e,c.relname,a.attname,a.atttypid,a.attnotnull  OR (t.typtype = 'd' AND",
        " t.typnotnull) AS attnotnull,a.atttypmod,a.attlen,t.typtypmod,row_numb",
        "er() OVER (PARTITION BY a.attrelid ORDER BY a.attnum) AS attnum, nulli",
        "f(a.attidentity, '') as attidentity,nullif(a.attgenerated, '') as attg",
        "enerated,pg_catalog.pg_get_expr(def.adbin, def.adrelid) AS adsrc,dsc.d",
        "escription,t.typbasetype,t.typtype  FROM pg_catalog.pg_namespace n  JO",
        "IN pg_catalog.pg_class c ON (c.relnamespace = n.oid)  JOIN pg_catalog.",
        "pg_attribute a ON (a.attrelid=c.oid)  JOIN pg_catalog.pg_type t ON (a.",
        "atttypid = t.oid)  LEFT JOIN pg_catalog.pg_attrdef def ON (a.attrelid=",
        "def.adrelid AND a.attnum = def.adnum)  LEFT JOIN pg_catalog.pg_descrip",
        "tion dsc ON (c.oid=dsc.objoid AND a.attnum = dsc.objsubid)  LEFT JOIN ",
        "pg_catalog.pg_class dc ON (dc.oid=dsc.classoid AND dc.relname='pg_clas",
        "s')  LEFT JOIN pg_catalog.pg_namespace dn ON (dc.relnamespace=dn.oid A",
        "ND dn.nspname='pg_catalog')  WHERE c.relkind in ('r','p','v','f','m') ",
        "and a.attnum > 0 AND NOT a.attisdropped  AND n.nspname LIKE ? AND c.re",
        "lname LIKE ?) c WHERE true  ORDER BY nspname,c.relname,attnum "
    ];
    string javaTables, javaColumns;
    foreach (part; javaTablesParts)
        javaTables ~= part;
    foreach (part; javaColumnsParts)
        javaColumns ~= part;
    string[] args;
    assert(tablesSql(null, "owners", null, args) == javaTables);
    assert(args == ["owners"]);
    args = null;
    assert(columnsSql("public", "owners", null, args) == javaColumns);
    assert(args == ["public", "owners"]);

    // Every pattern becomes a parameter, in pgjdbc's order; a type list adds its clauses.
    args = null;
    const typed = tablesSql("pub%", "own%", ["TABLE", "VIEW", "NO SUCH TYPE"], args);
    assert(args == ["pub%", "own%"]);
    assert(contains(typed, " AND n.nspname LIKE ? AND c.relname LIKE ? AND (false  OR ( c.relkind = 'r'"));
    assert(contains(typed,
            " OR ( c.relkind = 'v' AND n.nspname <> 'pg_catalog' AND n.nspname <> " ~ "'information_schema' ) ) "));
    args = null;
    assert(contains(columnsSql(null, null, "first%", args), ") c WHERE true  AND attname LIKE ? ORDER BY"));
    assert(args == ["first%"]);
}

@("getColumns rows: pgjdbc's type codes, names, sizes and flags for petclinic's column kinds")
unittest
{
    // owners.id: integer, NOT NULL, DEFAULT nextval(...): pgjdbc reports serial, autoincrement.
    CatalogColumn id = {
        catalog: "petclinic", nspname: "public", relname: "owners", attname: "id", typtype: "b",
        adsrc: "nextval('owners_id_seq'::regclass)", atttypid: 23, atttypmod: -1, typtypmod: -1,
        attnum: 1, attnotnull: true
    };
    auto row = columnRow(id);
    assert(row[0].text == "petclinic" && row[3].text == "id");
    assert(row[4].integer == Types.INTEGER && row[5].text == "serial" && row[6].integer == 10);
    assert(row[8].integer == 0 && row[9].integer == 10 && row[10].integer == columnNoNulls);
    assert(row[15].kind == MetaValue.Kind.null_ && row[16].integer == 1 && row[17].text == "NO");
    assert(row[21].kind == MetaValue.Kind.null_ && row[22].text == "YES" && row[23].text == "NO");

}

@("getColumns rows: varchar, date and numeric sizes, as TypeInfoCache reports them")
unittest
{
    MetaValue[24] row;
    // owners.first_name: varchar(30), nullable: typmod is the length plus 4.
    CatalogColumn name = {
        nspname: "public", relname: "owners", attname: "first_name", typtype: "b", atttypid: 1043,
        atttypmod: 34, typtypmod: -1, attnum: 2
    };
    row = columnRow(name);
    assert(row[4].integer == Types.VARCHAR && row[5].text == "varchar" && row[6].integer == 30);
    assert(row[15].integer == 30 && row[10].integer == columnNullable && row[17].text == "YES");
    assert(row[22].text == "NO" && row[12].kind == MetaValue.Kind.null_);

    // pets.birth_date: date; a numeric without a declared scale has none; text has an unknown length.
    CatalogColumn date = {atttypid: 1082, atttypmod: -1, typtype: "b", attnum: 3};
    row = columnRow(date);
    assert(row[4].integer == Types.DATE && row[5].text == "date" && row[6].integer == 13);
    CatalogColumn numeric = {atttypid: 1700, atttypmod: -1, typtype: "b"};
    row = columnRow(numeric);
    assert(row[4].integer == Types.NUMERIC && row[6].integer == 0 && row[8].kind == MetaValue.Kind.null_);
    CatalogColumn decimal = {atttypid: 1700, atttypmod: ((10 << 16) | 2) + 4, typtype: "b"};
    row = columnRow(decimal);
    assert(row[6].integer == 10 && row[8].integer == 2);
    CatalogColumn text = {atttypid: 25, atttypmod: -1, typtype: "b"};
    assert(columnRow(text)[6].integer == int.max);
}

@("getColumns rows: arrays, enums, domains, generated and identity columns, and types outside pgjdbc's table")
unittest
{
    MetaValue[24] row;
    // Arrays, enums, domains, generated and identity columns, and a type outside the table.
    CatalogColumn array = {atttypid: 1007, atttypmod: -1, typtype: "b"};
    row = columnRow(array);
    assert(row[4].integer == Types.ARRAY && row[5].text == "_int4" && row[6].integer == 10);
    CatalogColumn enumerated = {atttypid: 90_000, atttypmod: -1, typtype: "e"};
    row = columnRow(enumerated);
    assert(row[4].integer == Types.VARCHAR && row[5].kind == MetaValue.Kind.null_);
    CatalogColumn domain = {
        atttypid: 90_001, atttypmod: -1, typtype: "d", typbasetype: 1043, typtypmod: 24
    };
    row = columnRow(domain);
    assert(row[4].integer == Types.DISTINCT && row[6].integer == 24 && row[21].integer == Types.VARCHAR);
    CatalogColumn generated = {
        atttypid: 20, atttypmod: -1, typtype: "b", attidentity: "a", attgenerated: "s"
    };
    row = columnRow(generated);
    assert(row[4].integer == Types.BIGINT && row[5].text == "int8");
    assert(row[22].text == "YES" && row[23].text == "YES");
    CatalogColumn other = {atttypid: 90_002, atttypmod: -1, typtype: "b"};
    assert(columnRow(other)[4].integer == Types.OTHER);
}
