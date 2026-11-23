// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/DatabaseDriverTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: PostgreSQL's driver class is Flint's `flint.postgresql.Driver` (the `flint:postgresql`
// package); D has no null string, so `fromJdbcUrl(null)` and `fromProductName(null)` pass an empty one.
module database_driver_upstream_test;

import flint.boot.jdbc : DatabaseDriver;

@safe:

@("DatabaseDriverTests.classNameForKnownDatabase")
unittest
{
    assert(DatabaseDriver.fromJdbcUrl("jdbc:postgresql://hostname/dbname").getDriverClassName()
            == "flint.postgresql.Driver");
}

@("DatabaseDriverTests.nullClassNameForUnknownDatabase")
unittest
{
    assert(DatabaseDriver.fromJdbcUrl("jdbc:unknowndb://hostname/dbname").getDriverClassName() is null);
}

@("DatabaseDriverTests.unknownOnNullJdbcUrl")
unittest
{
    assert(DatabaseDriver.fromJdbcUrl(null) == DatabaseDriver.UNKNOWN);
}

@("DatabaseDriverTests.failureOnMalformedJdbcUrl")
unittest
{
    import flint.java.lang : IllegalArgumentException;
    import std.algorithm.searching : canFind;

    bool thrown;
    try
        DatabaseDriver.fromJdbcUrl("malformed:url");
    catch (IllegalArgumentException e)
        thrown = e.msg.canFind("'url' must start with");
    assert(thrown);
}

@("DatabaseDriverTests.unknownOnNullProductName")
unittest
{
    assert(DatabaseDriver.fromProductName(null) == DatabaseDriver.UNKNOWN);
}


@("DatabaseDriverTests.databaseProductNameLookups")
unittest
{
    assert(DatabaseDriver.fromProductName("newone") == DatabaseDriver.UNKNOWN);
    assert(DatabaseDriver.fromProductName("H2") == DatabaseDriver.H2);
    assert(DatabaseDriver.fromProductName("HDB") == DatabaseDriver.HANA);
    assert(DatabaseDriver.fromProductName("HSQL Database Engine") == DatabaseDriver.HSQLDB);
    assert(DatabaseDriver.fromProductName("SQLite") == DatabaseDriver.SQLITE);
    assert(DatabaseDriver.fromProductName("MySQL") == DatabaseDriver.MYSQL);
    assert(DatabaseDriver.fromProductName("MariaDB") == DatabaseDriver.MARIADB);
    assert(DatabaseDriver.fromProductName("Oracle") == DatabaseDriver.ORACLE);
    assert(DatabaseDriver.fromProductName("PostgreSQL") == DatabaseDriver.POSTGRESQL);
    assert(DatabaseDriver.fromProductName("Redshift") == DatabaseDriver.REDSHIFT);
    assert(DatabaseDriver.fromProductName("Microsoft SQL Server") == DatabaseDriver.SQLSERVER);
    assert(DatabaseDriver.fromProductName("SQL SERVER") == DatabaseDriver.SQLSERVER);
    assert(DatabaseDriver.fromProductName("DB2") == DatabaseDriver.DB2);
    assert(DatabaseDriver.fromProductName("Firebird 2.5.WI") == DatabaseDriver.FIREBIRD);
    assert(DatabaseDriver.fromProductName("Firebird 2.1.LI") == DatabaseDriver.FIREBIRD);
    assert(DatabaseDriver.fromProductName("DB2/LINUXX8664") == DatabaseDriver.DB2);
    assert(DatabaseDriver.fromProductName("DB2 UDB for AS/400") == DatabaseDriver.DB2_AS400);
    assert(DatabaseDriver.fromProductName("DB3 XDB for AS/400") == DatabaseDriver.DB2_AS400);
    assert(DatabaseDriver.fromProductName("Teradata") == DatabaseDriver.TERADATA);
    assert(DatabaseDriver.fromProductName("Informix Dynamic Server") == DatabaseDriver.INFORMIX);
    assert(DatabaseDriver.fromProductName("Apache Phoenix") == DatabaseDriver.PHOENIX);
    assert(DatabaseDriver.fromProductName("ClickHouse") == DatabaseDriver.CLICKHOUSE);
}

@("DatabaseDriverTests.deprecatedDatabaseProductNameLookups")
unittest
{
    assert(DatabaseDriver.fromProductName("Apache Derby") == DatabaseDriver.DERBY);
}

@("DatabaseDriverTests.databaseJdbcUrlLookups")
unittest
{
    assert(DatabaseDriver.fromJdbcUrl("jdbc:newone://localhost") == DatabaseDriver.UNKNOWN);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:h2:~/sample") == DatabaseDriver.H2);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:hsqldb:hsql://localhost") == DatabaseDriver.HSQLDB);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:sqlite:sample.db") == DatabaseDriver.SQLITE);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:mysql://localhost:3306/sample") == DatabaseDriver.MYSQL);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:oracle:thin:@localhost:1521:orcl") == DatabaseDriver.ORACLE);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:postgresql://127.0.0.1:5432/sample") == DatabaseDriver.POSTGRESQL);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:redshift://examplecluster.abc123xyz789.us-west-2.redshift.amazonaws.com"
            ~ ":5439/sample") == DatabaseDriver.REDSHIFT);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:jtds:sqlserver://127.0.0.1:1433/sample") == DatabaseDriver.JTDS);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:sap:localhost") == DatabaseDriver.HANA);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:sqlserver://127.0.0.1:1433") == DatabaseDriver.SQLSERVER);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:firebirdsql://localhost/sample") == DatabaseDriver.FIREBIRD);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:firebird://localhost/sample") == DatabaseDriver.FIREBIRD);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:db2://localhost:50000/sample ") == DatabaseDriver.DB2);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:as400://localhost") == DatabaseDriver.DB2_AS400);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:teradata://localhost/SAMPLE") == DatabaseDriver.TERADATA);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:informix-sqli://localhost:1533/sample") == DatabaseDriver.INFORMIX);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:informix-direct://sample") == DatabaseDriver.INFORMIX);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:phoenix:localhost") == DatabaseDriver.PHOENIX);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:tc:mysql://localhost:3306/sample") == DatabaseDriver.TESTCONTAINERS);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:clickhouse://localhost:3306/sample") == DatabaseDriver.CLICKHOUSE);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:ch://localhost:3306/sample") == DatabaseDriver.CLICKHOUSE);
    assert(DatabaseDriver.fromJdbcUrl("jdbc:aws-wrapper:postgresql://127.0.0.1:5432/sample")
            == DatabaseDriver.AWS_WRAPPER);
}

@("DatabaseDriverTests.deprecatedDatabaseJdbcUrlLookups")
unittest
{
    assert(DatabaseDriver.fromJdbcUrl("jdbc:derby:sample") == DatabaseDriver.DERBY);
}

// Flint: the package providing a driver, for the databases Flint has drivers for.
@("FlintDatabaseDriverDependencies")
unittest
{
    assert(DatabaseDriver.POSTGRESQL.flintDependency() == "flint:postgresql");
    assert(DatabaseDriver.SQLITE.getDriverClassName() == "flint.sqlite.JDBC");
    assert(DatabaseDriver.SQLITE.flintDependency() == "flint:sqlite-jdbc");
    assert(DatabaseDriver.MYSQL.flintDependency() is null);
    assert(DatabaseDriver.DB2_AS400.getId() == "db2" && DatabaseDriver.SQLSERVER.getId() == "sqlserver");
    assert(DatabaseDriver.values().length == 22 && DatabaseDriver.AWS_WRAPPER.name() == "AWS_WRAPPER");
}
