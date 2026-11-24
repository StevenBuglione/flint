// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/health/DataSourceHealthIndicatorTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the database is in-memory SQLite through Flint's `FlintDataSource` (Boot's tests use
// HSQLDB through a `SingleConnectionDataSource`), so the product name is "SQLite"; the cases that open it need the
// pinned SQLite (FlintNativeSqlite). Mockito's mocks are `BlackHole` stubs whose metadata reports Boot's HSQLDB name.
module datasource_health_indicator_upstream_test;

import flint.boot.health.contributor : Health, Status;
import flint.boot.jdbc.health : DataSourceHealthIndicator;
import flint.engine.aot.any : Any;
import flint.java.sql : Connection, DatabaseMetaData;
import flint.javax.sql : DataSource;
import std.typecons : BlackHole;

@safe:

private string[] keysOf(Health health)
{
    import std.algorithm.sorting : sort;

    auto keys = health.getDetails().keySet().toArray();
    sort(keys);
    return keys;
}

private string detail(Health health, string key)
{
    return health.getDetails().get(key).get!string;
}

/// Mockito's `mock(Connection.class)`: `isValid` answers `valid`, `close` is counted.
private class StubConnection : BlackHole!Connection
{
    int closed;
    bool valid = true;

    override DatabaseMetaData getMetaData()
    {
        return new StubMetaData;
    }

    override bool isValid(int timeout)
    {
        return valid;
    }

    override void close()
    {
        closed++;
    }
}

private class StubMetaData : BlackHole!DatabaseMetaData
{
    override string getDatabaseProductName()
    {
        return "HSQL Database Engine";
    }
}

/// Mockito's `mock(DataSource.class)`, returning `connection`.
private class StubDataSource : BlackHole!DataSource
{
    private Connection connection;

    this(Connection connection)
    {
        this.connection = connection;
    }

    override Connection getConnection()
    {
        return connection;
    }
}

@("healthIndicatorCloseConnection") unittest
{
    auto indicator = new DataSourceHealthIndicator;
    auto connection = new StubConnection;
    indicator.setDataSource(new StubDataSource(connection));
    auto health = indicator.health();
    assert(health.getDetails().containsKey("database"));
    assert(connection.closed == 2, "the product name and isValid each borrow and close a connection");
}

@("healthIndicatorWithConnectionValidationFailure") unittest
{
    auto indicator = new DataSourceHealthIndicator;
    auto connection = new StubConnection;
    connection.valid = false;
    indicator.setDataSource(new StubDataSource(connection));
    auto health = indicator.health();
    assert(health.getStatus() == Status.DOWN);
    assert(keysOf(health) == ["database", "validationQuery"]);
    assert(detail(health, "database") == "HSQL Database Engine");
    assert(detail(health, "validationQuery") == "isValid()");
}

@("Flint: without a data source the indicator is UP with an unknown database") unittest
{
    auto health = new DataSourceHealthIndicator().health();
    assert(health.getStatus() == Status.UP);
    assert(detail(health, "database") == "unknown");
}

@("Flint: afterPropertiesSet requires the data source") unittest
{
    import flint.java.lang : IllegalStateException;

    bool thrown;
    try
        new DataSourceHealthIndicator().afterPropertiesSet();
    catch (IllegalStateException ex)
        thrown = ex.msg == "DataSource for DataSourceHealthIndicator must be specified";
    assert(thrown);
    new DataSourceHealthIndicator(new StubDataSource(new StubConnection)).afterPropertiesSet();
}

@("Flint: the validation query is kept") unittest
{
    auto indicator = new DataSourceHealthIndicator(new StubDataSource(new StubConnection), "SELECT 1");
    assert(indicator.getQuery() == "SELECT 1");
    indicator.setQuery(null);
    assert(indicator.getQuery() is null);
}

version (FlintNativeSqlite)
{
    import flint.engine.jdbc : FlintDataSource;

    // This test runner declares SQLite, as a Boot test's class path holds its embedded driver.
    shared static this()
    {
        import flint.engine.jdbc : enableSqlite;

        enableSqlite();
    }

    private FlintDataSource database(string name)
    {
        return new FlintDataSource("jdbc:sqlite:file:" ~ name ~ "?mode=memory&cache=shared");
    }

    @("healthIndicatorWithDefaultSettings") unittest
    {
        auto dataSource = database("healthDefault");
        scope (exit)
            dataSource.close();
        auto indicator = new DataSourceHealthIndicator;
        indicator.setDataSource(dataSource);
        auto health = indicator.health();
        assert(health.getStatus() == Status.UP);
        assert(keysOf(health) == ["database", "validationQuery"]);
        assert(detail(health, "database") == "SQLite");
        assert(detail(health, "validationQuery") == "isValid()");
    }

    @("healthIndicatorWithCustomValidationQuery") unittest
    {
        import flint.jdbc.core : JdbcTemplate;

        auto dataSource = database("healthCustom");
        scope (exit)
            dataSource.close();
        const customValidationQuery = "SELECT COUNT(*) from FOO";
        new JdbcTemplate(dataSource).execute("CREATE TABLE FOO (id INTEGER PRIMARY KEY)");
        auto indicator = new DataSourceHealthIndicator;
        indicator.setDataSource(dataSource);
        indicator.setQuery(customValidationQuery);
        auto health = indicator.health();
        assert(health.getStatus() == Status.UP);
        assert(keysOf(health) == ["database", "result", "validationQuery"]);
        assert(detail(health, "database") == "SQLite");
        assert(detail(health, "validationQuery") == customValidationQuery);
        const result = health.getDetails().get("result");
        assert(result.holds!long && result.get!long == 0, result.toString());
    }

    @("healthIndicatorWithInvalidValidationQuery") unittest
    {
        auto dataSource = database("healthInvalid");
        scope (exit)
            dataSource.close();
        const invalidValidationQuery = "SELECT COUNT(*) from BAR";
        auto indicator = new DataSourceHealthIndicator;
        indicator.setDataSource(dataSource);
        indicator.setQuery(invalidValidationQuery);
        auto health = indicator.health();
        assert(health.getStatus() == Status.DOWN);
        assert(keysOf(health) == ["database", "error", "validationQuery"]);
        assert(detail(health, "database") == "SQLite");
        assert(detail(health, "validationQuery") == invalidValidationQuery);
    }
}
