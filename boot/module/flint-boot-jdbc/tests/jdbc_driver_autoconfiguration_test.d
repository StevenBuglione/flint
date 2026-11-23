// Flint's own tests for the JDBC driver declarations (Flint additions to the JDBC auto-configuration): Java finds a
// driver through the jar on the class path, and Flint links only the drivers an application declares (performance
// playbook S-1).
module jdbc_driver_autoconfiguration_test;

import flint.boot.autoconfigure.condition : ConditionalOnClass;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceBeanCreationException,
    DataSourceProperties, PostgresJdbcDriverAutoConfiguration, SqliteJdbcDriverAutoConfiguration;
import flint.engine.jdbc : driverEnabled;
import flint.java.sql : Driver, SQLException;
import std.traits : getUDAs;

@safe:

// This test runner declares SQLite, as a Boot test's class path holds its embedded driver: the other test modules
// build in-memory SQLite data sources. Nothing here enables PostgreSQL.
shared static this()
{
    import flint.engine.jdbc : enableSqlite;

    try
        enableSqlite();
    catch (SQLException ex)
    {
        // A build without SQLite: the cases below that need it check driverEnabled first.
    }
}

private string[] requiredClasses(T)()
{
    string[] names;
    static foreach (condition; getUDAs!(T, ConditionalOnClass))
        names ~= condition.name;
    return names;
}

private DataSourceProperties url(string value)
{
    auto properties = new DataSourceProperties;
    properties.setUrl(value);
    return properties;
}

@("each driver configuration is conditional on its declared driver class")
unittest
{
    assert(requiredClasses!PostgresJdbcDriverAutoConfiguration() == ["flint.postgresql.Driver"]);
    assert(requiredClasses!SqliteJdbcDriverAutoConfiguration() == ["flint.sqlite.JDBC"]);
}

@("an undeclared driver fails when the data source is created, naming the dependency")
unittest
{
    assert(!driverEnabled("jdbc:postgresql://db/app"));
    auto properties = url("jdbc:postgresql://db/app");
    try
    {
        new DataSourceAutoConfiguration().dataSource(properties);
        assert(false, "an undeclared PostgreSQL driver must fail at startup");
    }
    catch (DataSourceBeanCreationException ex)
    {
        assert(ex.msg == "Cannot load driver class: flint.postgresql.Driver (add the flint:postgresql dependency)",
                ex.msg);
        assert(ex.getProperties() is properties);
    }
}

@("a declared driver passes the data source's check")
unittest
{
    if (driverEnabled("jdbc:sqlite::memory:"))
        assert(new DataSourceAutoConfiguration().dataSource(url("jdbc:sqlite::memory:")) !is null);
}

@("the SQLite driver configuration enables the engine driver and supplies it")
unittest
{
    Driver driver;
    try
        driver = new SqliteJdbcDriverAutoConfiguration().flintSqliteJdbcDriver();
    catch (SQLException ex)
        return; // a build without SQLite
    assert(driverEnabled("jdbc:sqlite::memory:"));
    assert(driver.acceptsURL("jdbc:sqlite::memory:"));
}
