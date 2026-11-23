module sqlite_jdbc_tests;

import flint.engine.jdbc : driverEnabled;
import flint.java.sql : DriverManager, SQLException;
import flint.sqlite : JDBC;

@safe:

// The driver exists only where its native library does; without it, constructing it fails with 08001.
private JDBC driver()
{
    try
        return new JDBC;
    catch (SQLException ex)
    {
        assert(ex.getSQLState() == "08001");
        assert(!driverEnabled("jdbc:sqlite:x"));
        return null;
    }
}

@("JDBC enables the engine's SQLite driver when constructed")
unittest
{
    if (auto created = driver())
        assert(driverEnabled("jdbc:sqlite:x"));
}

@("JDBC accepts only jdbc:sqlite: URLs")
unittest
{
    if (auto created = driver())
    {
        assert(created.acceptsURL("jdbc:sqlite:x"));
        assert(!created.acceptsURL("jdbc:postgresql://db/app"));
        assert(!created.acceptsURL("jdbc:"));
        assert(created.connect("jdbc:postgresql://db/app", null) is null);
        assert(!created.jdbcCompliant());
        assert(created.getMajorVersion() >= 1);
    }
}

@("the module registers its driver with the DriverManager under its class name")
unittest
{
    if (driver() is null)
        return;
    bool found;
    foreach (registered; DriverManager.getDrivers())
        found |= typeid(cast(Object) registered).name == "flint.sqlite.JDBC";
    assert(found);
}
