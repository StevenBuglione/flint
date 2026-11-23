/++
`org.sqlite` (xerial's sqlite-jdbc, `org.xerial:sqlite-jdbc`): the JDBC driver class an application declares to
use SQLite.

Java finds a driver through the jar on the class path. Flint links only the drivers an application declares, so
this package is that declaration: Boot's DataSource auto-configuration enables the engine's SQLite driver when
`flint.sqlite.JDBC` is present, and constructing the class enables it too (performance playbook S-1). An application
without this dependency links none of the driver's native code (SQLite).
+/
module flint.sqlite;

import flint.engine.jdbc : FlintDriver, enableSqlite;
import flint.java.sql : Connection, Driver_ = Driver, DriverManager;
import flint.java.util : Properties;

@safe:

/// sqlite-jdbc's `org.sqlite.JDBC`: the JDBC driver for `jdbc:sqlite:` URLs, over Flint's engine driver.
final class JDBC : Driver_
{
    private FlintDriver engine;

    /// Enables the engine driver; throws `SQLException` (08001) when this build has no native library for it.
    this()
    {
        enableSqlite();
        engine = new FlintDriver;
    }

    /// A connection for `url`, or null when it is not a `jdbc:sqlite:` URL.
    override Connection connect(string url, Properties info)
    {
        return acceptsURL(url) ? engine.connect(url, info) : null;
    }

    /// Whether `url` starts with `jdbc:sqlite:`.
    override bool acceptsURL(string url)
    {
        return url.length >= "jdbc:sqlite:".length && url[0 .. "jdbc:sqlite:".length] == "jdbc:sqlite:";
    }

    /// The engine driver's major version.
    override int getMajorVersion()
    {
        return engine.getMajorVersion();
    }

    /// The engine driver's minor version.
    override int getMinorVersion()
    {
        return engine.getMinorVersion();
    }

    /// The engine driver does not claim JDBC compliance.
    override bool jdbcCompliant()
    {
        return false;
    }
}

private Driver_ supply()
{
    return new JDBC;
}

/// Registers the driver with the `DriverManager`, as the driver jar's `META-INF/services/java.sql.Driver` does; the
/// first lookup constructs it, which enables the engine driver.
shared static this()
{
    DriverManager.registerDriver(&supply);
}
