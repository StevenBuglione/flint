// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/main/java/org/springframework/boot/jdbc/DatabaseDriver.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the enum is a struct of static immutable constants with `name`, `ordinal` and
// `values`, as flint:web's `RequestMethod`; the constant-specific bodies (`getUrlPrefixes`, `matchProductName`,
// `getId`) are rows of one table. The driver class of a database Flint has a driver for is the Flint driver's
// (`flint.postgresql.Driver`, `flint.sqlite.JDBC`, the `flint:postgresql` and `flint:sqlite-jdbc` packages, named after
// the PgJDBC and xerial jars); every other class name, and every XA data source, is the JVM driver's, which Flint
// does not provide. `flintDependency` (Flint addition) names the package that provides a driver.

/// `org.springframework.boot.jdbc`: JDBC support for Boot.
module flint.boot.jdbc;

@safe:

/// Enumeration of common database drivers.
struct DatabaseDriver
{
    private ubyte index;

    /// Unknown type.
    static immutable DatabaseDriver UNKNOWN = DatabaseDriver(0);
    /// Apache Derby (deprecated since Boot 4.1.0, for removal).
    static immutable DatabaseDriver DERBY = DatabaseDriver(1);
    /// H2.
    static immutable DatabaseDriver H2 = DatabaseDriver(2);
    /// HyperSQL DataBase.
    static immutable DatabaseDriver HSQLDB = DatabaseDriver(3);
    /// SQLite.
    static immutable DatabaseDriver SQLITE = DatabaseDriver(4);
    /// MySQL.
    static immutable DatabaseDriver MYSQL = DatabaseDriver(5);
    /// MariaDB.
    static immutable DatabaseDriver MARIADB = DatabaseDriver(6);
    /// Oracle.
    static immutable DatabaseDriver ORACLE = DatabaseDriver(7);
    /// Postgres.
    static immutable DatabaseDriver POSTGRESQL = DatabaseDriver(8);
    /// Amazon Redshift.
    static immutable DatabaseDriver REDSHIFT = DatabaseDriver(9);
    /// HANA - SAP HANA Database - HDB.
    static immutable DatabaseDriver HANA = DatabaseDriver(10);
    /// jTDS. As it can be used for several databases, there isn't a single product name we could rely on.
    static immutable DatabaseDriver JTDS = DatabaseDriver(11);
    /// SQL Server.
    static immutable DatabaseDriver SQLSERVER = DatabaseDriver(12);
    /// Firebird.
    static immutable DatabaseDriver FIREBIRD = DatabaseDriver(13);
    /// DB2 Server.
    static immutable DatabaseDriver DB2 = DatabaseDriver(14);
    /// DB2 AS400 Server.
    static immutable DatabaseDriver DB2_AS400 = DatabaseDriver(15);
    /// Teradata.
    static immutable DatabaseDriver TERADATA = DatabaseDriver(16);
    /// Informix.
    static immutable DatabaseDriver INFORMIX = DatabaseDriver(17);
    /// Apache Phoenix.
    static immutable DatabaseDriver PHOENIX = DatabaseDriver(18);
    /// Testcontainers.
    static immutable DatabaseDriver TESTCONTAINERS = DatabaseDriver(19);
    /// ClickHouse.
    static immutable DatabaseDriver CLICKHOUSE = DatabaseDriver(20);
    /// AWS Advanced JDBC Wrapper.
    static immutable DatabaseDriver AWS_WRAPPER = DatabaseDriver(21);

    /// The constant's name.
    string name() const pure nothrow @nogc
    {
        return rows[index].name;
    }

    /// The constant's position.
    int ordinal() const pure nothrow @nogc
    {
        return index;
    }

    /// The name.
    string toString() const pure nothrow @nogc
    {
        return rows[index].name;
    }

    /// Every constant in declaration order.
    static DatabaseDriver[] values() pure nothrow
    {
        DatabaseDriver[] result;
        foreach (i; 0 .. rows.length)
            result ~= DatabaseDriver(cast(ubyte) i);
        return result;
    }

    /// The identifier of the driver: the lower-case name, except DB2_AS400's `db2`.
    string getId() const pure
    {
        import std.ascii : toLower;

        if (rows[index].id.length)
            return rows[index].id;
        char[] id;
        foreach (c; rows[index].name)
            id ~= toLower(c);
        return id.idup;
    }

    /// The driver class name, or `null`.
    string getDriverClassName() const pure nothrow @nogc
    {
        return rows[index].driverClassName;
    }

    /// The XA data source class name, or `null`.
    string getXaDataSourceClassName() const pure nothrow @nogc
    {
        return rows[index].xaDataSourceClassName;
    }

    /// The validation query, or `null`.
    string getValidationQuery() const pure nothrow @nogc
    {
        return rows[index].validationQuery;
    }

    /// The Flint package providing this database's driver (`flint:postgresql`), or `null` when Flint has none
    /// (Flint addition: what an application adds to its dependencies, as a Spring application adds the driver jar).
    string flintDependency() const pure nothrow @nogc
    {
        return rows[index].flintDependency;
    }

    /// The driver for the JDBC `url`, or `UNKNOWN`. Throws `IllegalArgumentException` unless `url` starts with
    /// "jdbc".
    static DatabaseDriver fromJdbcUrl(string url) pure
    {
        import flint.java.lang : IllegalArgumentException;
        import std.ascii : toLower;

        if (url.length == 0)
            return UNKNOWN;
        if (!hasPrefix(url, "jdbc"))
            throw new IllegalArgumentException("'url' must start with \"jdbc\"");
        char[] withoutPrefix;
        foreach (c; url["jdbc".length .. $])
            withoutPrefix ~= toLower(c);
        foreach (i, ref row; rows)
        {
            if (i == UNKNOWN.index)
                continue;
            foreach (urlPrefix; row.urlPrefixes.length ? row.urlPrefixes : [lowerName(row.name)])
                if (hasPrefix(withoutPrefix, ":" ~ urlPrefix ~ ":"))
                    return DatabaseDriver(cast(ubyte) i);
        }
        return UNKNOWN;
    }

    /// The driver for the database `productName`, or `UNKNOWN`.
    static DatabaseDriver fromProductName(string productName) pure
    {
        if (productName.length == 0)
            return UNKNOWN;
        foreach (i, ref row; rows)
            if (row.matches(productName))
                return DatabaseDriver(cast(ubyte) i);
        return UNKNOWN;
    }
}

private:

// One constant: its fields and the constant-specific bodies of `getId`, `getUrlPrefixes` and `matchProductName`.
struct Row
{
    string name;
    string productName;
    string driverClassName;
    string xaDataSourceClassName;
    string validationQuery;
    string[] urlPrefixes; // empty: the lower-case name
    string id; // empty: the lower-case name
    string alsoEquals; // matchProductName: another product name, ignoring case
    string alsoStartsWith; // matchProductName: a lower-case prefix
    string alsoContains; // matchProductName: a lower-case fragment
    string flintDependency;

    bool matches(string candidate) const pure
    {
        // Product names are ASCII, so an ASCII comparison ignoring case is std.uni's sicmp for them.
        if (productName.length && lowerName(productName) == lowerName(candidate))
            return true;
        if (alsoEquals.length && lowerName(alsoEquals) == lowerName(candidate))
            return true;
        const lower = lowerName(candidate);
        return (alsoStartsWith.length && hasPrefix(lower, alsoStartsWith))
            || (alsoContains.length && contains(lower, alsoContains));
    }
}

// Flint: plain loops, not std.algorithm or std.uni, whose objects pull std.net.curl and the rest of Phobos's
// network objects into every app (playbook S-9).

/// Whether `text` starts with `prefix`.
package(flint.boot) bool hasPrefix(scope const(char)[] text, scope const(char)[] prefix) pure nothrow @nogc
{
    return text.length >= prefix.length && text[0 .. prefix.length] == prefix;
}

/// Whether `text` contains `fragment`.
package(flint.boot) bool contains(scope const(char)[] text, scope const(char)[] fragment) pure nothrow @nogc
{
    if (fragment.length > text.length)
        return false;
    foreach (i; 0 .. text.length - fragment.length + 1)
        if (text[i .. i + fragment.length] == fragment)
            return true;
    return false;
}

string lowerName(string text) pure
{
    import std.ascii : toLower;

    char[] result;
    foreach (c; text)
        result ~= toLower(c);
    return result.idup;
}

static immutable Row[] rows = [
    Row("UNKNOWN"),
    Row("DERBY", "Apache Derby", "org.apache.derby.jdbc.EmbeddedDriver", "org.apache.derby.jdbc.EmbeddedXADataSource",
            "SELECT 1 FROM SYSIBM.SYSDUMMY1"),
    Row("H2", "H2", "org.h2.Driver", "org.h2.jdbcx.JdbcDataSource", "SELECT 1"),
    Row("HSQLDB", "HSQL Database Engine", "org.hsqldb.jdbc.JDBCDriver", "org.hsqldb.jdbc.pool.JDBCXADataSource",
            "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SYSTEM_USERS"),
    Row("SQLITE", "SQLite", "flint.sqlite.JDBC", null, null, null, null, null, null, null, "flint:sqlite-jdbc"),
    Row("MYSQL", "MySQL", "com.mysql.cj.jdbc.Driver", "com.mysql.cj.jdbc.MysqlXADataSource", "/* ping */ SELECT 1"),
    Row("MARIADB", "MariaDB", "org.mariadb.jdbc.Driver", "org.mariadb.jdbc.MariaDbDataSource", "SELECT 1"),
    Row("ORACLE", "Oracle", "oracle.jdbc.OracleDriver", "oracle.jdbc.xa.client.OracleXADataSource",
            "SELECT 'Hello' from DUAL"),
    Row("POSTGRESQL", "PostgreSQL", "flint.postgresql.Driver", "org.postgresql.xa.PGXADataSource", "SELECT 1", null,
            null, null, null, null, "flint:postgresql"),
    Row("REDSHIFT", "Redshift", "com.amazon.redshift.jdbc.Driver", null, "SELECT 1"),
    Row("HANA", "HDB", "com.sap.db.jdbc.Driver", "com.sap.db.jdbcext.XADataSourceSAP", "SELECT 1 FROM SYS.DUMMY", [
        "sap"
    ]),
    Row("JTDS", null, "net.sourceforge.jtds.jdbc.Driver"),
    Row("SQLSERVER", "Microsoft SQL Server", "com.microsoft.sqlserver.jdbc.SQLServerDriver",
            "com.microsoft.sqlserver.jdbc.SQLServerXADataSource", "SELECT 1", null, null, "SQL SERVER"),
    Row("FIREBIRD", "Firebird", "org.firebirdsql.jdbc.FBDriver", "org.firebirdsql.ds.FBXADataSource",
            "SELECT 1 FROM RDB$DATABASE", ["firebirdsql", "firebird"], null, null, "firebird"),
    Row("DB2", "DB2", "com.ibm.db2.jcc.DB2Driver", "com.ibm.db2.jcc.DB2XADataSource",
            "SELECT 1 FROM SYSIBM.SYSDUMMY1", null, null, null, "db2/"),
    Row("DB2_AS400", "DB2 UDB for AS/400", "com.ibm.as400.access.AS400JDBCDriver",
            "com.ibm.as400.access.AS400JDBCXADataSource", "SELECT 1 FROM SYSIBM.SYSDUMMY1", ["as400"], "db2",
            null, null, "as/400"),
    Row("TERADATA", "Teradata", "com.teradata.jdbc.TeraDriver"),
    Row("INFORMIX", "Informix Dynamic Server", "com.informix.jdbc.IfxDriver", null, "select count(*) from systables", [
        "informix-sqli", "informix-direct"
    ]),
    Row("PHOENIX", "Apache Phoenix", "org.apache.phoenix.jdbc.PhoenixDriver", null,
            "SELECT 1 FROM SYSTEM.CATALOG LIMIT 1"),
    Row("TESTCONTAINERS", null, "org.testcontainers.jdbc.ContainerDatabaseDriver", null, null, ["tc"]),
    Row("CLICKHOUSE", "ClickHouse", "com.clickhouse.jdbc.ClickHouseDriver", null, "SELECT 1", ["ch", "clickhouse"]),
    Row("AWS_WRAPPER", null, "software.amazon.jdbc.Driver", null, null, ["aws-wrapper"]),
];
