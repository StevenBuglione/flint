// Flint's own tests for the data source's driver check after the driver split: Java finds a driver through the jar on
// the class path, and Flint links only the drivers an application declares (performance playbook S-1).
module jdbc_driver_autoconfiguration_test;

import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceBeanCreationException,
    DataSourceProperties;
import flint.engine.jdbc : driverEnabled;
import flint.java.sql : Driver, SQLException;

@safe:

// This test runner declares SQLite, as a Boot test's class path holds its embedded driver: the other test modules
// build in-memory SQLite data sources. Nothing here enables PostgreSQL.
shared static this()
{
    import flint.engine.jdbc : enableSqlite;
    import flint.java.sql : DriverManager;

    try
        enableSqlite();
    catch (SQLException ex)
    {
        // A build without SQLite natives: the cases below that need it check driverEnabled first, and a stand-in
        // driver accepts SQLite URLs so that the modules configuring (never opening) SQLite data sources pass the
        // data source's driver check; the cases that open one are gated on FlintNativeSqlite.
        DriverManager.registerDriver(&supplySqliteStandIn);
    }
}

/// Accepts `jdbc:sqlite:` URLs in a build without the SQLite natives; connects to nothing.
private final class SqliteStandInDriver : Driver
{
    import flint.java.sql : Connection;
    import flint.java.util : Properties;

    override Connection connect(string url, Properties info)
    {
        return null;
    }

    override bool acceptsURL(string url)
    {
        import std.algorithm.searching : startsWith;

        return url.startsWith("jdbc:sqlite:");
    }

    override int getMajorVersion()
    {
        return 0;
    }

    override int getMinorVersion()
    {
        return 0;
    }

    override bool jdbcCompliant()
    {
        return false;
    }
}

private Driver supplySqliteStandIn()
{
    return new SqliteStandInDriver;
}

private DataSourceProperties url(string value)
{
    auto properties = new DataSourceProperties;
    properties.setUrl(value);
    return properties;
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
