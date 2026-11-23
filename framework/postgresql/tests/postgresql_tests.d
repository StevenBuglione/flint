module postgresql_tests;

import flint.engine.jdbc : driverEnabled;
import flint.java.sql : DriverManager, SQLException;
import flint.postgresql : Driver;

@safe:

// The driver exists only where its native library does; without it, constructing it fails with 08001.
private Driver driver()
{
    try
        return new Driver;
    catch (SQLException ex)
    {
        assert(ex.getSQLState() == "08001");
        assert(!driverEnabled("jdbc:postgresql:x"));
        return null;
    }
}

@("Driver enables the engine's PostgreSQL driver when constructed")
unittest
{
    if (auto created = driver())
        assert(driverEnabled("jdbc:postgresql:x"));
}

@("Driver accepts only jdbc:postgresql: URLs")
unittest
{
    if (auto created = driver())
    {
        assert(created.acceptsURL("jdbc:postgresql:x"));
        assert(!created.acceptsURL("jdbc:sqlite::memory:"));
        assert(!created.acceptsURL("jdbc:"));
        assert(created.connect("jdbc:sqlite::memory:", null) is null);
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
        found |= typeid(cast(Object) registered).name == "flint.postgresql.Driver";
    assert(found);
}
